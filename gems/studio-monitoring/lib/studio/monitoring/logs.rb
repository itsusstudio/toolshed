module Studio
  module Monitoring
    # The studio interface to Rails.logger, for free text a person reads in the
    # app's own log output. Lines here never reach AppSignal or PostHog; anything
    # worth searching or charting is an Event.
    module Logs
      class << self
        [:debug, :info, :warn, :error].each do |level|
          define_method(level) do |message = nil, &block|
            ::Rails.logger.public_send(level, message, &block)
          end
        end
      end
    end
  end
end
