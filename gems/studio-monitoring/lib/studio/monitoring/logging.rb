module Studio
  # Event names are the flow in snake_case, object first (billing_checkout_return,
  # job_performed), never prose. Log search and dashboards filter on the name, so
  # renaming one breaks every query behind it.
  module Monitoring
    module Logging
      QUOTABLE = /[\s"=]/

      class << self
        def backends
          Monitoring.config.log_backends.map { |name| Backends::ALL.fetch(name) }
        end

        def log_debug(caller_obj, message, properties: {})
          log(:debug, caller_obj, message, properties) if ::Rails.logger.debug?
        end

        def log_info(caller_obj, message, properties: {})
          log(:info, caller_obj, message, properties)
        end

        def log_warn(caller_obj, message, properties: {})
          log(:warn, caller_obj, message, properties)
        end

        def log_error(caller_obj, message, properties: {})
          log(:error, caller_obj, message, properties)
        end

        private

        def log(level, caller_obj, message, properties)
          payload = {source: caller_obj.is_a?(Module) ? caller_obj.name : caller_obj.class.name}
            .merge(Monitoring.default_properties)
            .merge(properties)
            .compact

          line = "#{message} #{logfmt(payload)}".strip
          backends.each { |backend| backend.log(level, line, message: message, payload: payload) }
        end

        def logfmt(payload)
          payload.map { |key, value| "#{key}=#{encode(value)}" }.join(" ")
        end

        def encode(value)
          string = value.to_s
          string.match?(QUOTABLE) ? string.inspect : string
        end
      end
    end
  end
end
