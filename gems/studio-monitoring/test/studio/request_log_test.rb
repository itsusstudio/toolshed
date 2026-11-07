require "test_helper"

class Studio::Monitoring::RequestLogTest < ActiveSupport::TestCase
  test "#add logs the request with the serving controller action as its source" do
    Studio::Monitoring::Events.expects(:info).with("http_request", has_entries(source: "RecipesController#index", status: 200))

    Studio::Monitoring::RequestLog::Logger.new.info(controller: "RecipesController", action: "index", status: 200)
  end

  test "#add logs server errors at error level" do
    Studio::Monitoring::Events.expects(:error).with("http_request", has_entries(source: "RecipesController#show"))

    Studio::Monitoring::RequestLog::Logger.new.info(controller: "RecipesController", action: "show", status: 500)
  end
end
