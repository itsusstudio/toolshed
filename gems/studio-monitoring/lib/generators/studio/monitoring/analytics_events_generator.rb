require "rails/generators"
require "rails/generators/active_record"

module Studio
  module Monitoring
    class AnalyticsEventsGenerator < ::Rails::Generators::Base
      include ::ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      def create_migration_file
        migration_template "create_analytics_events.rb.tt", File.join(db_migrate_path, "create_analytics_events.rb")
      end
    end
  end
end
