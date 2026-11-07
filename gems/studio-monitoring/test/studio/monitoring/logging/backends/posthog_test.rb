require "test_helper"

class Studio::Monitoring::Logging::Backends::PosthogTest < ActiveSupport::TestCase
  test "#log emits an OpenTelemetry record linked to the person and session replay" do
    TestContext.user_id = 42
    Studio::Monitoring::Current.analytics_session_id = "sess-1"
    logger = mock("otel logger")
    logger.expects(:on_emit).with(
      severity_text: "WARN",
      severity_number: 13,
      body: "recipe_import",
      attributes: {"recipe_id" => 7, "at" => "2026-11-06", "posthogDistinctId" => 42, "sessionId" => "sess-1"}
    )
    backend = Studio::Monitoring::Logging::Backends::Posthog.new
    backend.stubs(:logger).returns(logger)

    backend.log(:warn, "recipe_import recipe_id=7", message: "recipe_import", payload: {recipe_id: 7, at: Date.new(2026, 11, 6)})
  end
end
