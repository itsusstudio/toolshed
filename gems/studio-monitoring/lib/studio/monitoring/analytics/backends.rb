require_relative "backends/posthog"
require_relative "backends/database"

module Studio
  module Monitoring
    module Analytics
      module Backends
        ALL = {posthog: Posthog.new, database: Database.new}.freeze
      end
    end
  end
end
