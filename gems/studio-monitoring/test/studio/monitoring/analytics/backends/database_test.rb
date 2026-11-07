require "test_helper"

class Studio::Monitoring::Analytics::Backends::DatabaseTest < ActiveSupport::TestCase
  teardown { Studio::Monitoring::AnalyticsEvent.delete_all }

  test "#track stores the event with its actor and tenant in their own columns" do
    TestContext.shop_id = 7

    Studio::Monitoring::Analytics::Backends::Database.new.track("recipe_saved", actor_id: 42,
      properties: {actor_id: 42, tenant_id: 7, recipe_id: 3})

    event = Studio::Monitoring::AnalyticsEvent.sole
    assert_equal ["recipe_saved", 42, 7], [event.event_name, event.actor_id, event.tenant_id]
    assert_equal({"recipe_id" => 3}, event.properties)
  end

  test "is reachable by name from Analytics.track" do
    Studio::Monitoring.config.stubs(:analytics_backends).returns([:database])

    Studio::Monitoring::Analytics.track("session_started", actor_id: 1)

    assert_equal "session_started", Studio::Monitoring::AnalyticsEvent.sole.event_name
  end
end
