require "test_helper"

class Studio::Monitoring::EventsTest < ActiveSupport::TestCase
  test ".info, .warn and .error log at their level" do
    Rails.logger.expects(:info).with { |line| line.start_with?("checkout_return ") }
    Rails.logger.expects(:warn).with { |line| line.start_with?("checkout_return ") }
    Rails.logger.expects(:error).with { |line| line.start_with?("checkout_return ") }

    Studio::Monitoring::Events.info("checkout_return")
    Studio::Monitoring::Events.warn("checkout_return")
    Studio::Monitoring::Events.error("checkout_return")
  end

  test "the source is the app's call site, not Events" do
    Rails.logger.expects(:info).with { |line| line.include?("source=Studio::Monitoring::EventsTest#call_site") }

    call_site
  end

  test ".debug is skipped outside debug mode" do
    Rails.logger.expects(:debug).never

    Studio::Monitoring::Events.debug("sql_plan")
  end

  test ".debug logs at debug level in debug mode" do
    Rails.logger.expects(:debug).with { |line| line.start_with?("sql_plan ") && line.include?("source=Studio::Monitoring::EventsTest#debug_call_site") }

    Rails.event.with_debug { debug_call_site }
  end

  test "payload passes through Rails.event, so secrets are filtered" do
    Rails.logger.expects(:info).with { |line| line.include?("reset_token=[FILTERED]") }

    Studio::Monitoring::Events.info("password_reset", reset_token: "abc")
  end

  private

  def call_site
    Studio::Monitoring::Events.info("checkout_return")
  end

  def debug_call_site
    Studio::Monitoring::Events.debug("sql_plan")
  end
end
