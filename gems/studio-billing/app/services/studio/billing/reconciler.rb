module Studio
  module Billing
    class Reconciler
      class CursorExpiredError < StandardError; end

      EVENT_TYPES = [
        "customer.subscription.created", "customer.subscription.updated", "customer.subscription.deleted"
      ].freeze
      EVENT_RETENTION = 30.days
      CURSOR_NAME = "subscription_events"

      def initialize(client: Billing.client)
        @client = client
      end

      def reconcile_changes
        cursor = SyncCursor.for(CURSOR_NAME)
        if cursor.checked_at < EVENT_RETENTION.ago
          raise CursorExpiredError, "studio-billing: subscription events were last checked " \
            "#{cursor.checked_at.iso8601}, longer ago than Stripe keeps events, so changes may be missing. " \
            "Run bin/rails studio_billing:reconcile_all."
        end

        filters = {types: EVENT_TYPES, limit: 100, ending_before: cursor.last_event_id}.compact
        events = client.v1.events.list(filters).auto_paging_each.to_a

        events.map { it.data.object.id }.uniq.each { sync(it) }

        newest = events.max_by(&:created)
        cursor.last_event_id = newest.id if newest
        cursor.update!(checked_at: Time.current)
        events.size
      end

      def reconcile_all
        count = 0
        client.v1.subscriptions.list({status: "all", limit: 100}).auto_paging_each do |stripe_subscription|
          sync_object(stripe_subscription)
          count += 1
        end
        SyncCursor.reset(CURSOR_NAME)
        count
      end

      private

      attr_reader :client

      def sync(stripe_subscription_id)
        sync_object(client.v1.subscriptions.retrieve(stripe_subscription_id))
      rescue => e
        Rails.error.report(e, handled: true, context: {stripe_subscription_id: stripe_subscription_id})
      end

      def sync_object(stripe_subscription)
        SubscriptionSync.new(client: client).call(stripe_subscription)
      rescue => e
        Rails.error.report(e, handled: true, context: {stripe_subscription_id: stripe_subscription.id})
      end
    end
  end
end
