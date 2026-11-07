require "logger"

module Studio
  module Monitoring
    # One http_request event per request, built by lograge.
    module RequestLog
      class << self
        def setup(app, config)
          lograge = app.config.lograge
          lograge.enabled = !::Rails.env.local?
          lograge.ignore_actions = config.unlogged_actions
          lograge.ignore_custom = ->(event) { event.payload[:request]&.path == Configuration::HEALTH_CHECK_PATH }
          lograge.custom_options = custom_options(ActiveSupport::ParameterFilter.new(app.config.filter_parameters))
          return if !lograge.enabled

          lograge.keep_original_rails_log = true
          lograge.formatter = ::Lograge::Formatters::Raw.new
          lograge.logger = Logger.new
        end

        private

        def custom_options(param_filter)
          lambda do |event|
            params = event.payload[:params]&.except("controller", "action")
            request = event.payload[:request]
            {
              path: request && Redaction.masked_path(request),
              params: params && param_filter.filter(params).to_json,
              host: event.payload[:host],
              cf_ray: request&.get_header("HTTP_CF_RAY"),
              # Personal data kept on purpose, to trace abuse back to its
              # source. FILTER_PARAMETERS filters :remote_ip, not client_ip.
              client_ip: request&.remote_ip,
              exception: event.payload[:exception]&.first,
              exception_message: event.payload[:exception_object]&.message
            }.compact
          end
        end
      end

      class Logger < ::Logger
        def initialize
          super(nil)
        end

        # Logger#info(hash) arrives here as add(INFO, nil, hash).
        def add(severity, message = nil, progname = nil)
          request = message || progname || (yield if block_given?)
          level = (request[:status].to_i >= 500) ? :error : :info
          Events.public_send(level, "http_request", **request, source: "#{request[:controller]}##{request[:action]}")
          true
        end
      end
    end
  end
end
