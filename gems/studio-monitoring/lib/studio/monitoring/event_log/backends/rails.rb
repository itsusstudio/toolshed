module Studio
  module Monitoring
    module EventLog
      module Backends
        class Rails
          def log(level, line, **)
            ::Rails.logger.public_send(level, line)
          end
        end
      end
    end
  end
end
