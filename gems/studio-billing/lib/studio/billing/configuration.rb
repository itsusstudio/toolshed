module Studio
  module Billing
    class Configuration
      class Error < StandardError; end

      DEFAULT_WEBHOOK_EVENTS = [
        "checkout.session.completed",
        "customer.subscription.created",
        "customer.subscription.updated",
        "customer.subscription.deleted",
        "invoice.paid",
        "invoice.payment_failed",
        "charge.dispute.created",
        "charge.refunded",
        "radar.early_fraud_warning.created"
      ].freeze

      INTEGRATION_IDENTIFIER_FORMAT = /\A[a-z0-9_]+_[a-z]{8}\z/
      USAGE_PERIODS = [:month].freeze

      UsageCounter = Data.define(:name, :per, :counter) do
        def count(owner, now: Time.current)
          (per == :month) ? counter.call(owner, now.all_month) : counter.call(owner)
        end
      end

      attr_accessor :api_key, :api_version, :product_name, :webhook_secret, :webhook_url, :integration_identifier,
        :owner_from_metadata, :portal_configuration_id
      attr_writer :catalog_path, :webhook_events, :automatic_tax, :ui_mode,
        :open_timeout, :read_timeout, :write_timeout, :grace_period, :queue, :webhook_event_retention,
        :owner_classes
      attr_reader :usage_counters

      def initialize
        @usage_counters = {}
      end

      def catalog_path = @catalog_path || ::Rails.root.join("config/billing.yml")
      def webhook_events = @webhook_events || DEFAULT_WEBHOOK_EVENTS
      def automatic_tax = @automatic_tax || false
      def ui_mode = @ui_mode || "embedded_page"
      def open_timeout = @open_timeout || 2
      def read_timeout = @read_timeout || 10
      def write_timeout = @write_timeout || 10
      def grace_period = @grace_period || 3.days
      def queue = @queue || :less_than_five_minutes
      def owner_classes = @owner_classes || ["Organization"]
      def webhook_event_retention = @webhook_event_retention || 90.days

      def usage(name, per: nil, &counter)
        if per && !USAGE_PERIODS.include?(per)
          raise Error, "studio-billing: c.usage per: is :month or left out, not #{per.inspect}"
        end
        raise Error, "studio-billing: c.usage(#{name.inspect}) needs a block that counts" if !counter

        @usage_counters[name.to_s] = UsageCounter.new(name: name.to_s, per: per, counter: counter)
      end

      def validate_config!
        if integration_identifier.present? && !integration_identifier.match?(INTEGRATION_IDENTIFIER_FORMAT)
          raise Error, "studio-billing: c.integration_identifier is a lowercase label ending in _ and 8 random " \
            "letters, like \"workbench_signup_qhzkdmwp\", not #{integration_identifier.inspect}"
        end

        if !grace_period.is_a?(ActiveSupport::Duration)
          raise Error, "studio-billing: c.grace_period takes a duration, like 3.days"
        end
      end

      def validate_usage!(catalog)
        missing = catalog.limit_names - usage_counters.keys
        extra = usage_counters.keys - catalog.limit_names
        return if missing.empty? && extra.empty?

        problems = []
        problems << "no c.usage counter for #{missing.join(", ")}" if missing.any?
        problems << "c.usage counts #{extra.join(", ")}, which no plan limits" if extra.any?
        raise Error, "studio-billing: #{problems.join("; ")} in config/initializers/studio_billing.rb"
      end

      def validate_client_config!
        missing = [:api_key, :api_version, :product_name].select { |setting| public_send(setting).blank? }
        return if missing.empty?

        settings = missing.map { "c.#{it}" }.join(", ")
        raise Error, "studio-billing: set #{settings} in config/initializers/studio_billing.rb"
      end

      def validate_webhook_config!
        return if webhook_secret.present?

        raise Error, "studio-billing: set c.webhook_secret in config/initializers/studio_billing.rb"
      end

      def validate_portal_config!
        return if portal_configuration_id.present?

        raise Error, "studio-billing: set c.portal_configuration_id (bpc_...) in " \
          "config/initializers/studio_billing.rb to the customer portal configuration made in the Stripe Dashboard"
      end
    end
  end
end
