require "test_helper"

class Studio::Monitoring::LogsTest < ActiveSupport::TestCase
  test "each level writes the message to Rails.logger" do
    Rails.logger.expects(:info).with("Imported 3 recipes")
    Rails.logger.expects(:warn).with("Retrying import")

    Studio::Monitoring::Logs.info("Imported 3 recipes")
    Studio::Monitoring::Logs.warn("Retrying import")
  end

  test "a block message is passed on so it is only built when the level is on" do
    logger = ActiveSupport::Logger.new(StringIO.new)
    logger.level = :info
    Rails.stubs(:logger).returns(logger)
    built = false

    Studio::Monitoring::Logs.debug { built = true }

    assert_not built
  end

  test "lines do not reach the log backends" do
    Studio::Monitoring::EventLog::Backends::ALL[:appsignal].expects(:log).never

    Studio::Monitoring::Logs.info("Imported 3 recipes")
  end
end
