module Studio
  module Billing
    class Cancellation
      def initialize(client: Billing.client)
        @client = client
      end

      def call(owner, at_period_end: false)
        subscriptions = owner.billing_subscriptions.not_ended.map do |subscription|
          stripe_subscription = at_period_end ? stop_renewing(subscription) : cancel_now(subscription)
          SubscriptionSync.new(client: client).call(stripe_subscription)
        end
        owner.billing_grants.active.find_each(&:revoke!) if !at_period_end
        subscriptions
      end

      private

      attr_reader :client

      def cancel_now(subscription)
        client.v1.subscriptions.cancel(subscription.stripe_subscription_id)
      rescue Stripe::InvalidRequestError
        stripe_subscription = client.v1.subscriptions.retrieve(subscription.stripe_subscription_id)
        raise if !Subscription::ENDED_STATUSES.include?(stripe_subscription.status)

        stripe_subscription
      end

      def stop_renewing(subscription)
        client.v1.subscriptions.update(subscription.stripe_subscription_id, {cancel_at_period_end: true})
      end
    end
  end
end
