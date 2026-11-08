require "test_helper"

class AnalyticsTagController < ApplicationController
  def show
    Studio::Monitoring::Current.actor_id = params[:actor_id]
    Studio::Monitoring::Current.tenant_id = params[:tenant_id]
    render inline: "<%= studio_analytics_tag(properties: {platform: 'web', plan: nil}) %>"
  end
end

class Studio::Monitoring::BrowserAnalyticsTest < ActionDispatch::IntegrationTest
  Config = Studio::Monitoring::Configuration

  def app
    DummyApp
  end

  setup do
    Studio::Monitoring.config.stubs(:posthog).returns(Config::PosthogProject.new(token: "phc_1", host: "https://us.i.posthog.com"))
    Studio::Monitoring.config.stubs(:posthog_browser).returns(Config::PosthogBrowser.new(host: "https://e.example.com", ui_host: "https://us.posthog.com", defaults: "2026-05-30"))
  end

  test "renders the snippet with the project, hosts and registered properties" do
    get "/analytics_tag"

    script = script_tag
    assert_equal "phc_1", script["data-posthog-token"]
    assert_equal "https://e.example.com", script["data-posthog-host"]
    assert_equal "https://us.posthog.com", script["data-posthog-ui-host"]
    assert_equal "2026-05-30", script["data-posthog-defaults"]
    assert_equal [], JSON.parse(script["data-posthog-masked-paths"])
    assert_equal({"platform" => "web"}, JSON.parse(script["data-posthog-properties"]))
    assert_includes script.text, "posthog.init"
    assert_nil script["data-posthog-user-id"]
  end

  test "identifies the browser as the current actor in the tenant's group" do
    get "/analytics_tag", params: {actor_id: 42, tenant_id: 7}

    assert_equal "42", script_tag["data-posthog-user-id"]
    assert_equal "7", script_tag["data-posthog-tenant-id"]
  end

  test "passes the app's masked paths so the browser cuts token URLs to their prefix" do
    Studio::Monitoring.config.stubs(:posthog_masked_paths).returns(["/t/", "/passwords/"])

    get "/analytics_tag"

    assert_equal ["/t/", "/passwords/"], JSON.parse(script_tag["data-posthog-masked-paths"])
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
