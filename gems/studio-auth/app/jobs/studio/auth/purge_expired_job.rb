module Studio
  module Auth
    class PurgeExpiredJob < ActiveJob::Base # standard:disable Rails/ApplicationJob -- a gem has no ApplicationJob
      queue_as :less_than_five_hours

      def perform
        ::Session.expired.in_batches(of: 1_000).delete_all
        LoginCode.purgeable.in_batches(of: 1_000).delete_all
        KnownDevice.where(last_seen_at: ...KnownDevice::TRUST_PERIOD.ago).in_batches(of: 1_000).delete_all
      end
    end
  end
end
