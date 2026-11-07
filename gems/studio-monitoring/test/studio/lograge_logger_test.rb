require "test_helper"

class Studio::Monitoring::LogrageLoggerTest < ActiveSupport::TestCase
  test "#add logs the request with the serving controller action as its source" do
    Studio::Monitoring::Logging.expects(:log_info).with(Studio::Monitoring::LogrageLogger, "http_request",
      properties: has_entry(source: "RecipesController#index"))

    Studio::Monitoring::LogrageLogger.new.info(controller: "RecipesController", action: "index", status: 200)
  end

  test "#add logs server errors at error level" do
    Studio::Monitoring::Logging.expects(:log_error).with(Studio::Monitoring::LogrageLogger, "http_request",
      properties: has_entry(source: "RecipesController#show"))

    Studio::Monitoring::LogrageLogger.new.info(controller: "RecipesController", action: "show", status: 500)
  end
end
