require "rails"
require "active_support"
require "active_support/core_ext"
require "active_record"
require "active_job"
require "action_controller"
require "bigdecimal"
require "money"
require "stripe"

require_relative "billing/configuration"
require_relative "billing/catalog"
require_relative "billing/prices"
require_relative "billing/sync"
require_relative "billing/webhook"
require_relative "billing/routes"
require_relative "billing/for_organization"

module Studio
  module Billing
    class OrganizationNotFoundError < StandardError; end
    class UnknownPriceError < StandardError; end
    class BillingStillActiveError < StandardError; end
    class CheckoutSessionMismatchError < StandardError; end
    class StripeCustomerMismatchError < StandardError; end

    ORGANIZATION_METADATA_KEY = "studio_billing_organization_id"

    class << self
      def configure
        yield config
        config
      end

      def config
        @config ||= Configuration.new
      end

      def client
        @client ||= begin
          config.validate_client_config!
          Stripe::StripeClient.new(config.api_key, stripe_version: config.api_version)
        end
      end

      def catalog
        @catalog ||= Catalog.load(config.catalog_path)
      end

      def find_organization(id)
        ::Organization.find_by(id: id) if id.present?
      end

      def organization_for_checkout_session(session)
        organization_id = session.client_reference_id.to_s
        metadata = session.metadata.to_h.transform_keys(&:to_s)
        return if organization_id.blank? || metadata[ORGANIZATION_METADATA_KEY] != organization_id

        find_organization(organization_id)
      end

      def organization_for_stripe_customer(stripe_customer_id)
        ::Organization.find_by(stripe_customer_id: stripe_customer_id) if stripe_customer_id.present?
      end

      def reset!
        @config = nil
        @client = nil
        @catalog = nil
      end
    end
  end
end

require_relative "billing/engine"
