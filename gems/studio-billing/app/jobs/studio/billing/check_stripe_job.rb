module Studio
  module Billing
    class CheckStripeJob < ActiveJob::Base # standard:disable Rails/ApplicationJob
      class DriftError < StandardError; end

      queue_as { Billing.config.queue }

      def perform
        sync = Sync.new
        return if sync.in_sync?

        differences = sync.changes.reject(&:note?).map(&:to_s)
        Rails.error.report(
          DriftError.new("studio-billing: Stripe differs from config/billing.yml in #{differences.size} places"),
          handled: true,
          severity: :warning,
          context: {differences: differences}
        )
      end
    end
  end
end
