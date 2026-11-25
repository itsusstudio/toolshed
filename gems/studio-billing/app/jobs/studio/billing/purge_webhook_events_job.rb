module Studio
  module Billing
    class PurgeWebhookEventsJob < ActiveJob::Base # standard:disable Rails/ApplicationJob
      queue_as { Billing.config.queue }

      def perform
        WebhookEvent.where(created_at: ...Billing.config.webhook_event_retention.ago).in_batches.delete_all
      end
    end
  end
end
