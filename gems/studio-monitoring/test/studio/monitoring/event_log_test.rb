require "test_helper"

class Studio::Monitoring::EventLogTest < ActiveSupport::TestCase
  test "Rails.event lines carry the source, actor, tenant and app properties" do
    Studio::Monitoring::Current.actor_id = 42
    Studio::Monitoring::Current.tenant_id = 7
    TestContext.platform = "ios"

    Rails.logger.expects(:info).with { |line|
      line.start_with?("recipe_url_import ") && line.include?("source=") &&
        line.include?("actor_id=42") && line.include?("tenant_id=7") && line.include?("platform=ios")
    }

    Rails.event.notify("recipe_url_import")
  end

  test "Rails' own framework events are not logged, since the gem logs requests and jobs itself" do
    Rails.logger.expects(:info).never

    Rails.event.notify("action_controller.request_completed", controller: "HealthController")
    Rails.event.notify("active_job.enqueued", job_class: "PingJob")
  end

  test "app events with a dot in the name are still logged" do
    Rails.logger.expects(:info).with { |line| line.start_with?("twilio.inbound ") }

    Rails.event.notify("twilio.inbound")
  end

  test "lines carry the request and job ids so they join their request or job line" do
    Studio::Monitoring::Current.request_id = "req-1"
    Studio::Monitoring::Current.job_id = "job-1"

    Rails.logger.expects(:info).with { |line| line.include?("request_id=req-1") && line.include?("job_id=job-1") }

    Rails.event.notify("bulk_import")
  end

  test "lines carry Rails.event context and tags" do
    Rails.logger.expects(:info).with { |line| line.include?("section=checkout") && line.include?("graphql=true") }

    Rails.event.set_context(section: "checkout")
    Rails.event.tagged(graphql: true) { Rails.event.notify("checkout_return") }
  ensure
    Rails.event.clear_context
  end

  test "lines omit keys that are nil" do
    Rails.logger.expects(:info).with { |line| !line.include?("actor_id") && !line.include?("tenant_id") && !line.include?("platform") }

    Rails.event.notify("recipe_url_import")
  end

  test "values with spaces are quoted so logfmt parses them as one attribute" do
    Rails.logger.expects(:info).with { |line| line.include?('reason="page has too little content"') }

    Rails.event.notify("recipe_import", reason: "page has too little content")
  end

  test "payload overrides the defaults" do
    Rails.logger.expects(:info).with { |line| line.include?("locale=fr") }

    Rails.event.notify("recipe_import", locale: "fr")
  end

  test "secrets in the payload are filtered by Rails" do
    Rails.logger.expects(:info).with { |line| line.include?("reset_token=[FILTERED]") }

    Rails.event.notify("password_reset", reset_token: "abc")
  end

  test "level: sets the log level and is not logged itself" do
    Rails.logger.expects(:warn).with { |line| line.start_with?("recipe_import ") && !line.include?("level=") }

    Rails.event.notify("recipe_import", level: :warn)
  end

  test "an unknown level raises" do
    assert_raises(ArgumentError) do
      Studio::Monitoring::EventLog::Subscriber.new.emit({name: "x", payload: {level: :loud}, context: {}, tags: {}})
    end
  end

  test "every backend gets the level, line, event name and properties" do
    backend = mock("backend")
    backend.expects(:log).with { |level, line, message:, payload:|
      level == :info && line.start_with?("recipe_import") && message == "recipe_import" && payload[:recipe_id] == 7
    }
    Studio::Monitoring::EventLog.stubs(:backends).returns([backend])

    Rails.event.notify("recipe_import", recipe_id: 7)
  end
end
