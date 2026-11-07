require_relative "backends/rails"
require_relative "backends/appsignal"
require_relative "backends/posthog"

module Studio
  module Monitoring
    module Logging
      module Backends
        ALL = {rails: Rails.new, appsignal: Appsignal.new, posthog: Posthog.new}.freeze
      end
    end
  end
end
