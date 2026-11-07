require "test_helper"

class AnalyticsTagController < ApplicationController
  def show
    Studio::Monitoring::Current.actor_id = params[:actor_id]
    render inline: "<%= studio_analytics_tag(properties: {platform: 'web', plan: nil}) %>"
  end

  def sign_out
    reset_analytics_identity
    redirect_to "/analytics_tag"
  end
end

class Studio::Monitoring::BrowserAnalyticsTest < ActionDispatch::IntegrationTest
  Config = Studio::Monitoring::Configuration

  def app
    DummyApp
  end

  setup do
    Studio::Monitoring.config.stubs(:posthog).returns(Config::PosthogProject.new(token: "phc_1", host: "https://us.i.posthog.com"))
    Studio::Monitoring.config.stubs(:posthog_browser).returns(Config::PosthogBrowser.new(host: "https://e.example.com", ui_host: "https://us.posthog.com"))
  end

  test "renders the snippet with the project, hosts and registered properties" do
    get "/analytics_tag"

    script = script_tag
    assert_equal "phc_1", script["data-posthog-token"]
    assert_equal "https://e.example.com", script["data-posthog-host"]
    assert_equal "https://us.posthog.com", script["data-posthog-ui-host"]
    assert_equal({"platform" => "web"}, JSON.parse(script["data-posthog-properties"]))
    assert_includes script.text, "posthog.init"
    assert_nil script["data-posthog-user-id"]
    assert_nil script["data-posthog-reset"]
  end

  test "identifies the browser as the current actor" do
    get "/analytics_tag", params: {actor_id: 42}

    assert_equal "42", script_tag["data-posthog-user-id"]
  end

  test "the page after a sign-out resets the browser identity, once" do
    post "/sign_out"
    follow_redirect!

    assert_equal "true", script_tag["data-posthog-reset"]

    get "/analytics_tag"
    assert_nil script_tag["data-posthog-reset"]
  end

  test "renders nothing without a browser setup" do
    Studio::Monitoring.config.stubs(:posthog_browser).returns(nil)

    get "/analytics_tag"

    assert_empty response.body.strip
  end

  private

  def script_tag
    Nokogiri::HTML5.fragment(response.body).at_css("script")
  end
end
