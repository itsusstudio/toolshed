require "test_helper"
require "studio/monitoring/test_helper"

class Studio::Monitoring::TestHelperTest < ActiveSupport::TestCase
  include Studio::Monitoring::TestHelper

  teardown { Studio::Monitoring::AnalyticsEvent.delete_all }

  test "records analytics without sending to any backend" do
    Studio::Monitoring::Analytics::Backends::Posthog.any_instance.expects(:track).never

    assert_no_difference -> { Studio::Monitoring::AnalyticsEvent.count } do
      Studio::Monitoring::Analytics.track("recipe_saved", actor_id: 1, properties: {recipe_id: 7})
    end

    assert_analytics_tracked "recipe_saved", actor_id: 1, properties: {recipe_id: 7}
  end

  test "assert_analytics_tracked matches a subset of properties, including default properties and false values" do
    TestContext.platform = "ios"

    Studio::Monitoring::Analytics.track("recipe_saved", properties: {recipe_id: 7, is_copy: false})

    assert_analytics_tracked "recipe_saved", properties: {is_copy: false, platform: "ios"}
    assert_analytics_tracked "recipe_saved", properties: {recipe_id: 7, locale: /en/}
  end

  test "assert_analytics_tracked fails with what was tracked" do
    Studio::Monitoring::Analytics.track("recipe_saved", actor_id: 1)

    error = assert_raises(Minitest::Assertion) { assert_analytics_tracked "recipe_saved", actor_id: 2 }

    assert_match "recipe_saved", error.message
    assert_match "actor_id=1", error.message.tr(":", "=").gsub(/\s/, "")
  end

  test "a block limits assertions to what it tracked" do
    Studio::Monitoring::Analytics.track("recipe_saved")

    assert_no_analytics_tracked {}
    assert_raises(Minitest::Assertion) do
      assert_analytics_tracked("recipe_saved") { Studio::Monitoring::Analytics.track("recipe_viewed") }
    end
  end

  test "assert_no_analytics_tracked checks one event name or all of them" do
    Studio::Monitoring::Analytics.track("recipe_saved")

    assert_no_analytics_tracked "recipe_viewed"
    assert_raises(Minitest::Assertion) { assert_no_analytics_tracked }
  end

  test "identify and llm generations are recorded" do
    Studio::Monitoring::Analytics.identify(actor_id: 3, properties: {timezone: "UTC"})
    Studio::Monitoring::Analytics.track_llm_generation(actor_id: 3, kind: "recipe_extraction", model: "m")

    assert_analytics_identified actor_id: 3, properties: {timezone: "UTC"}
    assert_analytics_tracked "$ai_generation", actor_id: 3, properties: {kind: "recipe_extraction"}
  end

  test "use_analytics_backends sends to real backends and keeps recording" do
    use_analytics_backends(:database)

    Studio::Monitoring::Analytics.track("recipe_saved", actor_id: 1)

    assert_equal "recipe_saved", Studio::Monitoring::AnalyticsEvent.sole.event_name
    assert_analytics_tracked "recipe_saved"
  end

  test "use_analytics_backends with a block only lasts for the block" do
    use_analytics_backends(:database) { Studio::Monitoring::Analytics.track("inside") }
    Studio::Monitoring::Analytics.track("outside")

    assert_equal ["inside"], Studio::Monitoring::AnalyticsEvent.pluck(:event_name)
  end

  test "use_analytics_backends rejects an unknown backend" do
    assert_raises(KeyError) { use_analytics_backends(:segment) }
  end

  test "records counters and durations" do
    Studio::Monitoring::Metrics.increment_counter("recipe_url_import", tags: {ok: true, source: nil})
    Studio::Monitoring::Metrics.record_duration("recipe_url_import.duration", 120, tags: {ok: true})

    assert_counter_incremented "recipe_url_import", by: 1, tags: {ok: true}
    assert_duration_recorded "recipe_url_import.duration", tags: {ok: true}
    assert_no_metric_recorded "checkout"
    assert_raises(Minitest::Assertion) { assert_counter_incremented "recipe_url_import", by: 2 }
  end

  test "Rails' event assertions see the level and the filtered payload" do
    assert_event_reported("checkout_return", payload: {level: :warn, success: false, email: "[FILTERED]"}) do
      Studio::Monitoring::Events.warn("checkout_return", success: false, email: "a@b.c")
    end
  end
end

class Studio::Monitoring::TestHelperOffTest < ActiveSupport::TestCase
  test "without the helper, analytics use the configured backends" do
    assert_nil Studio::Monitoring::TestHelper.recorder
    assert_equal [Studio::Monitoring::Analytics::Backends::ALL.fetch(:posthog)], Studio::Monitoring::Analytics.backends
  end
end
