require "rails"
require "active_support"
require "active_support/core_ext"
require "active_record"
require "active_job"
require "action_controller"
require "global_id"
require "bigdecimal"
require "money"
require "stripe"

require_relative "billing/configuration"
require_relative "billing/catalog"
require_relative "billing/prices"
require_relative "billing/sync"
require_relative "billing/webhook"
require_relative "billing/routes"
require_relative "billing/for_owner"

module Studio
  module Billing
    class OwnerNotFoundError < StandardError; end
    class UnknownPriceError < StandardError; end
    class BillingStillActiveError < StandardError; end

    OWNER_METADATA_KEY = "studio_billing_owner"

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

      def locate_owner(global_id)
        return if global_id.blank?

        GlobalID::Locator.locate(global_id, only: owner_classes)
      rescue ActiveRecord::RecordNotFound
        nil
      end

      def owner_for_stripe_customer(stripe_customer_id)
        return if stripe_customer_id.blank?

        owner_classes.lazy.filter_map { it.find_by(stripe_customer_id: stripe_customer_id) }.first
      end

      def owner_classes
        config.owner_classes.map(&:constantize)
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
