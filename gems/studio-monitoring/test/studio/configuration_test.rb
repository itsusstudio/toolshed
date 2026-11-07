require "test_helper"

class Studio::Monitoring::ConfigurationTest < ActiveSupport::TestCase
  setup do
    @config = Studio::Monitoring::Configuration.new
  end

  test "#validate! raises without a service name" do
    error = assert_raises(ArgumentError) { @config.validate! }
    assert_match "c.service_name", error.message
  end

  test "PostHog is off until a project is given" do
    assert_nil @config.posthog
  end

  test "#posthog_project stores the token and host" do
    @config.posthog_project(token: "phc_1", host: "https://us.i.posthog.com")

    assert_equal "phc_1", @config.posthog.token
    assert_equal "https://us.i.posthog.com", @config.posthog.host
  end

  test "#posthog_project raises when one of token or host is blank" do
    assert_raises(ArgumentError) { @config.posthog_project(token: "phc_1", host: "") }
    assert_raises(ArgumentError) { @config.posthog_project(token: nil, host: "https://us.i.posthog.com") }
  end

  test "backend and ignore lists start as defaults apps can add to" do
    @config.unlogged_actions += ["AppController#ping"]

    assert_includes @config.unlogged_actions, "Rails::HealthController#show"
    assert_includes @config.unlogged_actions, "AppController#ping"
    assert_equal [:rails, :appsignal, :posthog], @config.log_backends
    assert_equal [:posthog], @config.analytics_backends
  end

  test "#validate! raises on a backend the gem does not ship" do
    @config.service_name = "dummy"
    @config.analytics_backends += [:mixpanel]

    error = assert_raises(ArgumentError) { @config.validate! }
    assert_match ":mixpanel", error.message
    assert_match ":database", error.message
  end

  test "#validate! accepts every shipped backend" do
    @config.service_name = "dummy"
    @config.analytics_backends = [:posthog, :database]

    assert_nothing_raised { @config.validate! }
  end
end
