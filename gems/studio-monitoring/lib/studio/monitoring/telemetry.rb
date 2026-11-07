module Studio
  module Monitoring
    # Defaults use ||= so an OTEL_* env var set on the host still wins.
    module Telemetry
      TRACE_SAMPLE_RATE = "0.25"
      HISTOGRAM_BUCKETS_MS = [10, 25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000, 20_000, 30_000, 60_000].freeze

      class << self
        def setup(config, env: ::Rails.env)
          default_env(config, env)
          configure_sdk(config, env) if enabled?
        end

        def enabled?
          ENV["OTEL_SDK_DISABLED"] != "true"
        end

        def endpoint
          ENV.fetch("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")
        end

        def untraced_requests(paths)
          prefixes, patterns = paths.partition { |path| path.is_a?(String) }
          ->(env) {
            path = env["PATH_INFO"]
            path.start_with?(*prefixes) || patterns.any? { |pattern| pattern.match?(path) }
          }
        end

        private

        def configure_sdk(config, env)
          OpenTelemetry.logger = ::Logger.new($stdout, level: ::Logger::WARN)

          OpenTelemetry::SDK.configure do |sdk|
            sdk.service_name = config.service_name
            sdk.service_version = ENV["RENDER_GIT_COMMIT"] if ENV["RENDER_GIT_COMMIT"]
            sdk.resource = OpenTelemetry::SDK::Resources::Resource.create("deployment.environment" => env.to_s)

            sdk.use_all(
              "OpenTelemetry::Instrumentation::Rack" => {
                untraced_endpoints: [Configuration::HEALTH_CHECK_PATH, "/cable"],
                untraced_requests: untraced_requests(config.untraced_paths)
              },
              # posthog-ruby sends from a background thread, so each batch would
              # otherwise be its own root span.
              "OpenTelemetry::Instrumentation::Net::HTTP" => {untraced_hosts: [URI(endpoint).host]}
            )
          end

          OpenTelemetry.tracer_provider.sampler = RequestAndJobSampler.new(OpenTelemetry.tracer_provider.sampler)
          OpenTelemetry.tracer_provider.add_span_processor(Redaction::QuerySpanProcessor.new)

          # Default buckets stop at 1 s, too short for p95 of slow work. The SDK
          # ignores bucket hints on instrument creation, so it takes a view.
          OpenTelemetry.meter_provider.add_view("*", type: :histogram,
            aggregation: OpenTelemetry::SDK::Metrics::Aggregation::ExplicitBucketHistogram.new(boundaries: HISTOGRAM_BUCKETS_MS))
        end

        def default_env(config, env)
          if config.posthog
            ENV["OTEL_EXPORTER_OTLP_ENDPOINT"] ||= "#{config.posthog.host}/i"
            ENV["OTEL_EXPORTER_OTLP_HEADERS"] ||= "Authorization=Bearer #{config.posthog.token}"
            ENV["OTEL_TRACES_SAMPLER"] ||= "parentbased_traceidratio"
            ENV["OTEL_TRACES_SAMPLER_ARG"] ||= TRACE_SAMPLE_RATE
          elsif env.development?
            ENV["OTEL_LOGS_EXPORTER"] ||= "none"
            ENV["OTEL_METRICS_EXPORTER"] ||= "none"
          else
            ENV["OTEL_SDK_DISABLED"] ||= "true"
          end
        end
      end

      # Solid Queue and Solid Cable poll the database from their own threads,
      # so every polling query would start its own trace. Only requests
      # (server) and jobs (consumer) may start one.
      class RequestAndJobSampler
        def initialize(delegate)
          @delegate = delegate
        end

        def should_sample?(trace_id:, parent_context:, links:, name:, kind:, attributes:)
          parent = OpenTelemetry::Trace.current_span(parent_context).context
          if !parent.valid? && kind != :server && kind != :consumer
            OpenTelemetry::SDK::Trace::Samplers::Result.new(
              decision: OpenTelemetry::SDK::Trace::Samplers::Decision::DROP,
              tracestate: parent.tracestate
            )
          else
            @delegate.should_sample?(trace_id: trace_id, parent_context: parent_context,
              links: links, name: name, kind: kind, attributes: attributes)
          end
        end

        def description
          "RequestAndJobSampler{#{@delegate.description}}"
        end
      end
    end
  end
end
