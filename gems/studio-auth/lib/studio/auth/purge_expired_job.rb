module Studio
  module Auth
    class PurgeExpiredJob < ActiveJob::Base # standard:disable Rails/ApplicationJob -- a gem has no ApplicationJob
      def perform
        ::Session.expired.in_batches(of: 1_000).delete_all
        LoginChallenge.purgeable.in_batches(of: 1_000).delete_all
        KnownDevice.where(last_seen_at: ...SESSION_ABSOLUTE_TIMEOUT.ago).in_batches(of: 1_000).delete_all
      end
    end
  end
end
