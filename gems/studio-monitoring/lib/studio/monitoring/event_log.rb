module Studio
  module Monitoring
    # Turns every Rails.event into one logfmt line on the configured backends.
    module EventLog
      LEVELS = [:debug, :info, :warn, :error].freeze
      QUOTABLE = /[\s"=]/
      # Rails 8.1 reports its own work on Rails.event too
      # (action_controller.request_completed and friends). The gem already
      # logs requests and jobs once each, and these skip unlogged_actions, so
      # health checks would land twice per hit.
      FRAMEWORK_EVENT = /\A(?:action|active)_[a-z]+\./

      class << self
        # Rails.event's own filter hook, so framework events never reach emit.
        def app_event?(event)
          !event[:name].to_s.match?(FRAMEWORK_EVENT)
        end

        def backends
          Monitoring.config.log_backends.map { |name| Backends::ALL.fetch(name) }
        end
      end

      class Subscriber
        def emit(event)
          payload = event[:payload].to_h.dup
          level = payload.delete(:level)&.to_sym || :info
          raise ArgumentError, "Rails.event level must be one of #{LEVELS.join(", ")}, got #{level.inspect}" if !LEVELS.include?(level)

          name = event[:name].to_s
          properties = {source: event.dig(:source_location, :label)}
            .merge(Monitoring.default_properties, event[:context], event[:tags], payload)
            .compact
          line = "#{name} #{logfmt(properties)}".strip

          EventLog.backends.each { |backend| backend.log(level, line, message: name, payload: properties) }
        end

        private

        def logfmt(properties)
          properties.map { |key, value| "#{key}=#{encode(value)}" }.join(" ")
        end

        def encode(value)
          string = value.to_s
          string.match?(QUOTABLE) ? string.inspect : string
        end
      end
    end
  end
end
