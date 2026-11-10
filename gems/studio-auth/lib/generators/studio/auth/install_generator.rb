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

        def schedule_purge
          entry = <<~YAML
            studio_auth_purge_expired:
              class: Studio::Auth::PurgeExpiredJob
              schedule: every day at 4am
          YAML
          path = "config/recurring.yml"
          full_path = File.join(destination_root, path)
          existing = File.exist?(full_path) ? File.read(full_path) : nil
          return if existing&.include?("Studio::Auth::PurgeExpiredJob")

          if existing.nil?
            create_file path, "default: &default\n#{entry.indent(2)}\nproduction:\n  <<: *default\n"
          elsif (env = existing[/^(default|production):.*\n/])
            inject_into_file path, entry.indent(2), after: env
          else
            append_to_file path, "\nproduction:\n#{entry.indent(2)}"
          end
        end

        def copy_pages
          directory "views", "app/views/studio/auth"
        end

        def create_page_translations
          ::I18n.available_locales.each do |locale|
            base = locale.to_s.split("-").first
            locales = File.join(self.class.source_root, "locales")
            source = File.exist?(File.join(locales, "#{base}.yml")) ? base : "en"
            body = File.read(File.join(locales, "#{source}.yml")).sub(/\A#{source}:/, "#{locale}:")
            create_file "config/locales/studio_auth.#{locale}.yml", body
          end
        end
      end
    end
  end
end
