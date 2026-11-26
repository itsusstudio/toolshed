require "rails/generators"
require "rails/generators/active_record"

module Studio
  module Billing
    module Generators
      class InstallGenerator < ::Rails::Generators::Base
        include ::ActiveRecord::Generators::Migration

        source_root File.expand_path("templates", __dir__)

        def create_migration_files
          migration_template "create_studio_billing.rb.tt", "db/migrate/create_studio_billing.rb"
          migration_template "add_stripe_customer_id_to_organizations.rb.tt",
            "db/migrate/add_stripe_customer_id_to_organizations.rb"
        end

        def include_organization_concern
          path = "app/models/organization.rb"
          full_path = File.join(destination_root, path)
          if !File.exist?(full_path)
            raise Thor::Error, "studio-billing bills an Organization model (app/models/organization.rb, " \
              "table organizations), and this app has none."
          end
          return if File.read(full_path).include?("Studio::Billing::ForOrganization")

          inject_into_class path, "Organization", "  include Studio::Billing::ForOrganization\n"
        end

        def create_initializer
          template "initializer.rb.tt", "config/initializers/studio_billing.rb"
        end

        def create_catalog
          template "billing.yml.tt", "config/billing.yml"
        end

        def add_routes
          route "studio_billing"
        end

        def schedule_jobs
          schedule("studio_billing_reconcile", "Studio::Billing::ReconcileSubscriptionsJob", "every hour")
          schedule("studio_billing_check_stripe", "Studio::Billing::CheckStripeJob", "every monday at 3am")
          schedule("studio_billing_purge_webhook_events", "Studio::Billing::PurgeWebhookEventsJob", "every day at 4am")
        end

        private

        def schedule(key, job_class, every)
          entry = "#{key}:\n  class: #{job_class}\n  schedule: #{every}\n"
          path = "config/recurring.yml"
          full_path = File.join(destination_root, path)
          existing = File.exist?(full_path) ? File.read(full_path) : nil
          return if existing&.include?(job_class)

          if existing.nil?
            create_file path, "default: &default\n#{entry.indent(2)}\nproduction:\n  <<: *default\n"
          elsif (env = existing[/^(default|production):.*\n/])
            inject_into_file path, entry.indent(2), after: env
          else
            append_to_file path, "\nproduction:\n#{entry.indent(2)}"
          end
        end
      end
    end
  end
end
