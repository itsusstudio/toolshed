module Studio
  module Monitoring
    class PurgeAnalyticsEventsJob < ActiveJob::Base # standard:disable Rails/ApplicationJob -- a gem has no ApplicationJob
      def perform
        AnalyticsEvent.where(created_at: ...AnalyticsEvent::RETENTION.ago).in_batches.delete_all
      end
    end
  end
end
