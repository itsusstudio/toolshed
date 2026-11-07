module Studio
  module Monitoring
    module Errors
      class << self
        def report(error, context: {}, source: nil)
          Rails.error.report(
            error,
            handled: true,
            context: Monitoring.default_properties.merge(context).compact,
            source: source
          )
        end
      end
    end
  end
end
