require "test_helper"

class Studio::Monitoring::AnalyticsTest < ActiveSupport::TestCase
  test ".track keeps going when one backend raises, so analytics never breaks the caller" do
    failing = mock("failing backend")
    failing.expects(:track).raises(StandardError, "posthog down")
    working = mock("working backend")
    working.expects(:track).with("recipe_saved", has_entries(actor_id: 1))
    Studio::Monitoring::Analytics.stubs(:backends).returns([failing, working])

    assert_nothing_raised { Studio::Monitoring::Analytics.track("recipe_saved", actor_id: 1) }
  end

  test ".track logs the failing backend" do
    failing = mock("failing backend")
    failing.expects(:track).raises(StandardError)
    Studio::Monitoring::Analytics.stubs(:backends).returns([failing])

    Studio::Monitoring::Logging.expects(:log_warn).with(Studio::Monitoring::Analytics, "analytics_backend",
      properties: has_entries(success: false, event_name: "recipe_saved"))

    Studio::Monitoring::Analytics.track("recipe_saved", actor_id: 1)
  end

  test ".track adds actor, tenant, app properties and locale, letting explicit properties override them" do
    TestContext.user_id = 42
    TestContext.shop_id = 3
    TestContext.platform = "ios"
    backend = mock("backend")
    backend.expects(:track).with("recipe_saved",
      has_entries(properties: {actor_id: 42, tenant_id: 3, platform: "ios", locale: "fr", recipe_id: 7}))
    Studio::Monitoring::Analytics.stubs(:backends).returns([backend])

    Studio::Monitoring::Analytics.track("recipe_saved", properties: {locale: "fr", recipe_id: 7})
  end

  test ".track defaults actor_id to the configured actor" do
    TestContext.user_id = 42
    backend = mock("backend")
    backend.expects(:track).with("session_started", has_entries(actor_id: 42))
    Studio::Monitoring::Analytics.stubs(:backends).returns([backend])

    Studio::Monitoring::Analytics.track("session_started")
  end

  test ".identify drops nil properties" do
    backend = mock("backend")
    backend.expects(:identify).with(actor_id: 42, properties: {timezone: "UTC"})
    Studio::Monitoring::Analytics.stubs(:backends).returns([backend])

    Studio::Monitoring::Analytics.identify(actor_id: 42, properties: {timezone: "UTC", acquisition_channel: nil})
  end

  test ".track_llm_generation skips backends that do not support it" do
    Studio::Monitoring::Analytics.stubs(:backends).returns([Object.new])

    assert_nothing_raised { Studio::Monitoring::Analytics.track_llm_generation(kind: "photo") }
  end

  test ".identify defaults actor_id to the configured actor" do
    TestContext.user_id = 42
    backend = mock("backend")
    backend.expects(:identify).with(actor_id: 42, properties: {})
    Studio::Monitoring::Analytics.stubs(:backends).returns([backend])

    Studio::Monitoring::Analytics.identify
  end
end
