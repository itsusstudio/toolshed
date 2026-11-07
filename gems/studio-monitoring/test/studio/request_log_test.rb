require "test_helper"

class Studio::Monitoring::RequestLogTest < ActiveSupport::TestCase
  test "#add logs the request with the serving controller action as its source" do
    Studio::Monitoring::Events.expects(:info).with("http_request", has_entries(source: "RecipesController#index", status: 200))

    Studio::Monitoring::RequestLog::Logger.new.info(controller: "RecipesController", action: "index", status: 200)
  end

  test ".setup logs the client IP with each request" do
    env = Rack::MockRequest.env_for("/recipes", "action_dispatch.remote_ip" => "203.0.113.50")
    event = ActiveSupport::Notifications::Event.new("process_action.action_controller", nil, nil, "1", {request: ActionDispatch::Request.new(env)})

    options = Studio::Monitoring::RequestLog.send(:custom_options, ActiveSupport::ParameterFilter.new([])).call(event)

    assert_equal "203.0.113.50", options[:client_ip]
  end

  test "#add logs server errors at error level" do
    Studio::Monitoring::Events.expects(:error).with("http_request", has_entries(source: "RecipesController#show"))

    Studio::Monitoring::RequestLog::Logger.new.info(controller: "RecipesController", action: "show", status: 500)
  end
end
