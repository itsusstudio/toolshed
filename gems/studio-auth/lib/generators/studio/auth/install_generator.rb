require "rails/generators"
require "rails/generators/active_record"

module Studio
  module Auth
    module Generators
      class InstallGenerator < ::Rails::Generators::Base
        include ::ActiveRecord::Generators::Migration

        source_root File.expand_path("templates", __dir__)

        def create_migration_file
          migration_template "create_studio_auth.rb.tt", "db/migrate/create_studio_auth.rb"
        end

        def create_initializer
          template "initializer.rb.tt", "config/initializers/studio_auth.rb"
        end

        def add_routes
          route "studio_auth"
        end

        def copy_pages
          directory "views", "app/views/studio/auth"
        end

        # One file per locale the app offers, so page copy follows the app's
        # own locales and i18n tooling. Regional locales start from their base
        # language, anything else from English.
        def create_page_translations
          ::I18n.available_locales.each do |locale|
            base = locale.to_s.split("-").first
            source = File.exist?(File.join(self.class.source_root, "locales", "#{base}.yml")) ? base : "en"
            body = File.read(File.join(self.class.source_root, "locales", "#{source}.yml")).sub(/\A#{source}:/, "#{locale}:")
            create_file "config/locales/studio_auth.#{locale}.yml", body
          end
        end
      end
    end
  end
end
