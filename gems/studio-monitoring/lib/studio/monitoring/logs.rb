module Studio
  module Monitoring
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
