module Studio
  module Monitoring
    # The studio interface to Rails.error. Default context comes from the
    # Railtie's Rails.error middleware, so errors Rails reports on its own get
    # it too.
    module Errors
      class << self
        def report(error, context: {}, **)
          ::Rails.error.report(error, context: context, **)
        end

        def handle(...)
          ::Rails.error.handle(...)
        end

        def record(...)
          ::Rails.error.record(...)
        end
      end
    end
  end
end
