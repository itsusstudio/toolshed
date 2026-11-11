require "rails"
require "studio/auth"
require "mission_control/jobs"
require "flipper/ui"
require "pghero"

module Studio
  module Admin
    class << self
      def config
        @config ||= Configuration.new
      end

      def configure
        yield config
      end
    end
  end
end

require "studio/admin/configuration"
require "studio/admin/staff_constraint"
require "studio/admin/admin_routes"
require "studio/admin/engine"
