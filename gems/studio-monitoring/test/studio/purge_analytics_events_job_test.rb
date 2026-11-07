require "test_helper"

class Studio::Monitoring::PurgeAnalyticsEventsJobTest < ActiveSupport::TestCase
  teardown { Studio::Monitoring::AnalyticsEvent.delete_all }

  test "deletes events older than the retention and keeps the rest" do
    Studio::Monitoring::AnalyticsEvent.create!(event_name: "old", created_at: 61.days.ago)
    Studio::Monitoring::AnalyticsEvent.create!(event_name: "recent", created_at: 59.days.ago)

    Studio::Monitoring::PurgeAnalyticsEventsJob.perform_now

    assert_equal ["recent"], Studio::Monitoring::AnalyticsEvent.pluck(:event_name)
  end
end
