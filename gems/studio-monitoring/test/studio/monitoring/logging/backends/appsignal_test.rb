require "test_helper"

class Studio::Monitoring::Logging::Backends::AppsignalTest < ActiveSupport::TestCase
  test "#log does nothing in local environments" do
    ::Appsignal::Logger.expects(:new).never

    Studio::Monitoring::Logging::Backends::Appsignal.new.log(:info, "test line")
  end

  test "#log ships app events to the events group outside local environments" do
    Rails.env.stubs(:local?).returns(false)
    appsignal_logger = mock("appsignal_logger")
    appsignal_logger.expects(:info).with("test line")
    ::Appsignal::Logger.expects(:new).with("events", format: ::Appsignal::Logger::LOGFMT).returns(appsignal_logger)

    Studio::Monitoring::Logging::Backends::Appsignal.new.log(:info, "test line", message: "recipe_import")
  end

  test "#log ships request lines to the rails group" do
    Rails.env.stubs(:local?).returns(false)
    appsignal_logger = mock("appsignal_logger")
    appsignal_logger.expects(:info).with("http_request status=200")
    ::Appsignal::Logger.expects(:new).with("rails", format: ::Appsignal::Logger::LOGFMT).returns(appsignal_logger)

    Studio::Monitoring::Logging::Backends::Appsignal.new.log(:info, "http_request status=200", message: "http_request")
  end
end
