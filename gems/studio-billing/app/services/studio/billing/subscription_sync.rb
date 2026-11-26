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
        organization = organization_of(stripe_subscription)
        return if !organization && Subscription::ENDED_STATUSES.include?(stripe_subscription.status)

        if !organization
          raise OrganizationNotFoundError,
            "studio-billing: no organization for Stripe subscription #{stripe_subscription.id} " \
            "(customer #{stripe_subscription.customer})"
        end

        plan_before = organization.entitlements.plan&.code
        attributes = {organization: organization, **Subscription.attributes_from(stripe_subscription)}
        subscription = ActiveRecord::Base.transaction do
          record_stripe_customer(organization, stripe_subscription.customer)
          Subscription.create_or_find_by!(stripe_subscription_id: stripe_subscription.id) do |record|
            record.assign_attributes(attributes)
          end.tap { it.update!(attributes) }
        end
        report_unknown_price(subscription) if subscription.plan_code.nil?

        ActiveSupport::Notifications.instrument(CHANGED_EVENT,
          organization: organization,
          subscription: subscription,
          plan_before: plan_before,
          plan_after: organization.entitlements.plan&.code)
        subscription
      end

      private

      attr_reader :client

      def record_stripe_customer(organization, stripe_customer_id)
        organization.record_stripe_customer(stripe_customer_id)
      rescue StripeCustomerMismatchError => error
        Rails.error.report(error, handled: true, severity: :warning)
      end

      def organization_of(stripe_subscription)
        metadata = stripe_subscription.metadata.to_h.transform_keys(&:to_s)

        Billing.find_organization(metadata[ORGANIZATION_METADATA_KEY]) ||
          Billing.organization_for_stripe_customer(stripe_subscription.customer) ||
          Billing.config.organization_from_metadata&.call(metadata)
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
