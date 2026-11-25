module Studio
  module Billing
    class ReconcileSubscriptionsJob < ActiveJob::Base # standard:disable Rails/ApplicationJob
      queue_as { Billing.config.queue }

      def perform
        Reconciler.new.reconcile_changes
      end
    end
  end
end
