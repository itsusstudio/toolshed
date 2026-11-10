require "rails/generators"
require "rails/generators/active_record"

module Studio
  module Tenancy
    module Generators
      class InstallGenerator < ::Rails::Generators::Base
        include ::ActiveRecord::Generators::Migration

        source_root File.expand_path("templates", __dir__)

        def create_migration_file
          migration_template "create_studio_tenancy.rb.tt", "db/migrate/create_studio_tenancy.rb"
        end

        def create_models
          template "organization.rb.tt", "app/models/organization.rb"
          template "organization_membership.rb.tt", "app/models/organization_membership.rb"
          template "workspace.rb.tt", "app/models/workspace.rb"
          template "workspace_membership.rb.tt", "app/models/workspace_membership.rb"
        end
      end
    end
  end
end
