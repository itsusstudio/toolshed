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

      def create_session(owner:, lookup_key:, return_url:)
        client.v1.checkout.sessions.create(session_params(owner:, lookup_key:, return_url:))
      end

      def session_params(owner:, lookup_key:, return_url:)
        price = sellable_price!(lookup_key)
        if owner.entitlements.subscription
          raise AlreadySubscribedError,
            "studio-billing: #{owner.billing_global_id} already has a subscription that counts"
        end

        stripe_customer_id = owner.stripe_customer_id
        metadata = {OWNER_METADATA_KEY => owner.billing_global_id}

        {
          mode: "subscription",
          ui_mode: config.ui_mode,
          line_items: [{price: Prices.id_for(price.lookup_key, client: client), quantity: 1}],
          customer: stripe_customer_id,
          customer_email: (owner.billing_email_address if !stripe_customer_id),
          customer_update: ({address: "auto", name: "auto"} if stripe_customer_id && config.automatic_tax),
          client_reference_id: owner.billing_global_id,
          metadata: metadata,
          subscription_data: {billing_mode: {type: "flexible"}, metadata: metadata},
          automatic_tax: {enabled: config.automatic_tax},
          branding_settings: catalog.checkout_branding_settings,
          integration_identifier: config.integration_identifier,
          **return_params(return_url)
        }.compact
      end

      def complete(session_id:)
        session = client.v1.checkout.sessions.retrieve(session_id)
        return Completion.new(status: session.status, subscription: nil) if session.status != "complete"

        owner = Billing.locate_owner(session.client_reference_id)
        raise OwnerNotFoundError, "studio-billing: no owner for Checkout Session #{session.id}" if !owner

        owner.record_stripe_customer(session.customer)
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
