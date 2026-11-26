module Studio
  module Billing
    class Checkout
      class NotForSaleError < StandardError; end
      class AlreadySubscribedError < StandardError; end

      Completion = Data.define(:status, :subscription) do
        def complete? = status == "complete"
      end

      def initialize(client: Billing.client, catalog: Billing.catalog, config: Billing.config)
        @client = client
        @catalog = catalog
        @config = config
      end

      def create_session(organization:, lookup_key:, return_url:)
        client.v1.checkout.sessions.create(session_params(organization:, lookup_key:, return_url:))
      end

      def session_params(organization:, lookup_key:, return_url:)
        price = sellable_price!(lookup_key)
        if organization.entitlements.subscription
          raise AlreadySubscribedError,
            "studio-billing: #{organization.id} already has a subscription that counts"
        end

        stripe_customer_id = organization.stripe_customer_id
        metadata = {ORGANIZATION_METADATA_KEY => organization.id.to_s}

        {
          mode: "subscription",
          ui_mode: config.ui_mode,
          line_items: [{price: Prices.id_for(price.lookup_key, client: client), quantity: 1}],
          customer: stripe_customer_id,
          customer_email: (organization.billing_email_address if !stripe_customer_id),
          customer_update: ({address: "auto", name: "auto"} if stripe_customer_id && config.automatic_tax),
          client_reference_id: organization.id.to_s,
          metadata: metadata,
          subscription_data: {billing_mode: {type: "flexible"}, metadata: metadata},
          automatic_tax: {enabled: config.automatic_tax},
          branding_settings: catalog.checkout_branding_settings,
          integration_identifier: config.integration_identifier,
          **return_params(return_url)
        }.compact
      end

      def complete(session_id:, organization:)
        session = client.v1.checkout.sessions.retrieve(session_id)
        if Billing.organization_for_checkout_session(session) != organization
          raise CheckoutSessionMismatchError,
            "studio-billing: Checkout Session #{session.id} isn't organization #{organization.id}'s"
        end
        return Completion.new(status: session.status, subscription: nil) if session.status != "complete"

        organization.record_stripe_customer(session.customer)
        subscription = SubscriptionSync.new(client: client)
          .call(client.v1.subscriptions.retrieve(session.subscription))
        Completion.new(status: session.status, subscription: subscription)
      end

      private

      attr_reader :client, :catalog, :config

      def sellable_price!(lookup_key)
        price = catalog.find_price(lookup_key)
        raise NotForSaleError, "studio-billing: #{lookup_key.inspect} isn't a price in config/billing.yml" if !price
        if catalog.find_plan(price.plan_code).legacy?
          raise NotForSaleError, "studio-billing: #{lookup_key} belongs to a legacy plan, which isn't sold"
        end

        price
      end

      def return_params(return_url)
        (config.ui_mode == "hosted_page") ? {success_url: return_url} : {return_url: return_url}
      end
    end
  end
end
