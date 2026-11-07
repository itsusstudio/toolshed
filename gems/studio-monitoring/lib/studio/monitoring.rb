require "active_support"
require "active_support/core_ext"
require "concurrent/map"
require "appsignal"
require "lograge"
require "posthog"
require "posthog-rails"
require "opentelemetry/sdk"
require "opentelemetry-logs-sdk"
require "opentelemetry-metrics-sdk"
require "opentelemetry/exporter/otlp"
require "opentelemetry-exporter-otlp-logs"
require "opentelemetry-exporter-otlp-metrics"
require "opentelemetry/instrumentation/rails"
require "opentelemetry/instrumentation/pg"
require "opentelemetry/instrumentation/net/http"

require_relative "monitoring/configuration"
require_relative "monitoring/filter_parameters"
require_relative "monitoring/current"
require_relative "monitoring/redaction"
require_relative "monitoring/telemetry"
require_relative "monitoring/posthog_client"
require_relative "monitoring/request_log"
require_relative "monitoring/request_sampling"
require_relative "monitoring/job_log"
require_relative "monitoring/event_log"
require_relative "monitoring/event_log/backends"
require_relative "monitoring/errors"
require_relative "monitoring/events"
require_relative "monitoring/logs"
require_relative "monitoring/metrics"
require_relative "monitoring/analytics"
require_relative "monitoring/analytics/backends"
require_relative "monitoring/browser_analytics"

module Studio
  module Monitoring
    # Active Record and Active Job classes, loaded on first use so requiring
    # the gem does not load those frameworks before the app configures them.
    autoload :AnalyticsEvent, "studio/monitoring/analytics_event"
    autoload :PurgeAnalyticsEventsJob, "studio/monitoring/purge_analytics_events_job"

    class << self
      def configure
        yield config
        config
      end

      def config
        @config ||= Configuration.new
      end

      def default_properties
        {
          request_id: Current.request_id,
          job_id: Current.job_id,
          actor_id: actor_id,
          tenant_id: tenant_id,
          **Monitoring.config.default_properties.call,
          locale: I18n.locale
        }.compact
      end

      def actor_id
        Current.actor_id
      end

      def tenant_id
        Current.tenant_id
      end

      def summary
        {
          service: config.service_name,
          posthog: config.posthog ? "on" : "off",
          posthog_browser: config.posthog_browser ? "on" : "off",
          log_backends: config.log_backends.join(","),
          analytics_backends: config.analytics_backends.join(","),
          otel: Telemetry.enabled? ? Telemetry.endpoint : "off",
          traces_sample: ENV["OTEL_TRACES_SAMPLER_ARG"],
          otel_logs: ENV["OTEL_LOGS_EXPORTER"],
          otel_metrics: ENV["OTEL_METRICS_EXPORTER"]
        }
      end
    end
  end
end

require_relative "monitoring/railtie" if defined?(Rails::Railtie)
