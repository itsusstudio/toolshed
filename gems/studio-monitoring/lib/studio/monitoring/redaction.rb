module Studio
  module Monitoring
    # Uses the app's filter_parameters, the same rule Rails applies to logs, so
    # traces and logs agree on what is secret.
    module Redaction
      FILTERED = "[FILTERED]"

      class << self
        # The route pattern (/t/:token) when a path parameter has a sensitive
        # name, so long-lived tokens in paths never reach traces or logs.
        def masked_path(request)
          return if request.path_parameters.keys.none? { |key| sensitive?(key) }

          request.route_uri_pattern&.chomp("(.:format)")
        end

        def filter_query(query)
          query.split("&").map { |pair|
            key, value = pair.split("=", 2)
            (value && sensitive?(CGI.unescape(key))) ? "#{key}=#{FILTERED}" : pair
          }.join("&")
        end

        def sensitive?(key)
          parameter_filter.filter(key.to_s => "x")[key.to_s] != "x"
        end

        def mask_current_span(request)
          path = masked_path(request)
          return if path.nil?

          span = OpenTelemetry::Instrumentation::Rack.current_span
          span.set_attribute("url.path", path) if span.recording?
        end

        private

        def parameter_filter
          @parameter_filter ||= ActiveSupport::ParameterFilter.new(::Rails.application.config.filter_parameters)
        end
      end

      # Rails filters url.query only for requests that reach a controller;
      # this covers the rest and outgoing HTTP calls. It runs in on_start
      # because the SDK holds the span's lock during on_finishing.
      class QuerySpanProcessor
        def on_start(span, _parent_context)
          query = span.attributes&.dig("url.query")
          span.set_attribute("url.query", Redaction.filter_query(query)) if query
        end

        def on_finish(_span)
        end

        def force_flush(timeout: nil)
          OpenTelemetry::SDK::Trace::Export::SUCCESS
        end

        def shutdown(timeout: nil)
          OpenTelemetry::SDK::Trace::Export::SUCCESS
        end
      end
    end
  end
end
