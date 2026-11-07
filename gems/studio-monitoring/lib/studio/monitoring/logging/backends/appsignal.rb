module Studio
  module Monitoring
    module Logging
      module Backends
        class Appsignal
          # AppSignal's lograge docs group request logs as "rails"; changing
          # either name splits existing log views.
          REQUEST_GROUP = "rails"
          EVENT_GROUP = "events"

          def log(level, line, message: nil, **)
            return if ::Rails.env.local?

            group = (message == "http_request") ? REQUEST_GROUP : EVENT_GROUP
            logger_for(group).public_send(level, line)
          end

          private

          def logger_for(group)
            @loggers ||= {}
            @loggers[group] ||= ::Appsignal::Logger.new(group, format: ::Appsignal::Logger::LOGFMT)
          end
        end
      end
    end
  end
end
