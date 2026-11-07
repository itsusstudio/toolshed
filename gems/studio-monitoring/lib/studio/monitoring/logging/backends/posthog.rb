module Studio
  module Monitoring
    module Logging
      module Backends
        class Posthog
          SEVERITY_NUMBERS = {debug: 5, info: 9, warn: 13, error: 17, fatal: 21}.freeze

          def log(level, line, message:, payload:)
            logger.on_emit(
              severity_text: level.to_s.upcase,
              severity_number: SEVERITY_NUMBERS[level],
              body: message,
              attributes: attributes(payload)
            )
          end

          private

          # PostHog links a log to its person and session replay only through
          # these two exact attribute names.
          def attributes(payload)
            payload
              .merge(posthogDistinctId: Monitoring.actor_id, sessionId: Current.analytics_session_id)
              .compact
              .to_h { |key, value| [key.to_s, otel_value(value)] }
          end

          def otel_value(value)
            case value
            when String, Integer, Float, true, false then value
            else value.to_s
            end
          end

          def logger
            OpenTelemetry.logger_provider.logger(name: Monitoring.config.service_name)
          end
        end
      end
    end
  end
end
