module Studio
  module Billing
    class SubscriptionSync
      CHANGED_EVENT = "studio_billing.subscription_changed"

      class << self
        def call(stripe_subscription_id, client: Billing.client)
          new(client: client).call(client.v1.subscriptions.retrieve(stripe_subscription_id))
        end
      end

      def initialize(client: Billing.client)
        @client = client
      end

      def call(stripe_subscription)
        owner = owner_of(stripe_subscription)
        return if !owner && Subscription::ENDED_STATUSES.include?(stripe_subscription.status)

        if !owner
          raise OwnerNotFoundError, "studio-billing: no owner for Stripe subscription #{stripe_subscription.id} " \
            "(customer #{stripe_subscription.customer})"
        end

        plan_before = owner.entitlements.plan&.code
        attributes = {owner: owner, **Subscription.attributes_from(stripe_subscription)}
        subscription = ActiveRecord::Base.transaction do
          owner.record_stripe_customer(stripe_subscription.customer)
          Subscription.create_or_find_by!(stripe_subscription_id: stripe_subscription.id) do |record|
            record.assign_attributes(attributes)
          end.tap { it.update!(attributes) }
        end
        report_unknown_price(subscription) if subscription.plan_code.nil?

        ActiveSupport::Notifications.instrument(CHANGED_EVENT,
          owner: owner,
          subscription: subscription,
          plan_before: plan_before,
          plan_after: owner.entitlements.plan&.code)
        subscription
      end

      private

      attr_reader :client

      def owner_of(stripe_subscription)
        metadata = stripe_subscription.metadata.to_h.transform_keys(&:to_s)

        Billing.locate_owner(metadata[OWNER_METADATA_KEY]) ||
          Billing.owner_for_stripe_customer(stripe_subscription.customer) ||
          Billing.config.owner_from_metadata&.call(metadata)
      end

      def report_unknown_price(subscription)
        Rails.error.report(
          UnknownPriceError.new("studio-billing: Stripe price #{subscription.stripe_price_id} " \
            "(lookup key #{subscription.lookup_key.inspect}) isn't in config/billing.yml"),
          handled: true,
          context: {stripe_subscription_id: subscription.stripe_subscription_id}
        )
      end
    end
  end
end
