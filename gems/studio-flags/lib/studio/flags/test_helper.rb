module Studio
  module Flags
    # Registers every flag before each test, so Flipper's strict mode lets
    # tests check flags that no test enabled.
    module TestHelper
      extend ActiveSupport::Concern

      included do
        setup { Studio::Flags.sync! }
      end
    end
  end
end
