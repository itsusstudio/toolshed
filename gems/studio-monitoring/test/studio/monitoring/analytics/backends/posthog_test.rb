require "test_helper"

class Studio::Monitoring::Analytics::Backends::PosthogTest < ActiveSupport::TestCase
  setup do
    @client = mock("posthog client")
    @backend = Studio::Monitoring::Analytics::Backends::Posthog.new
    @backend.stubs(:client).returns(@client)
  end

  test "#track sends the browser session id so the event links to its replay" do
    Studio::Monitoring::Current.analytics_session_id = "sess-1"
    @client.expects(:capture).with do |attrs|
      attrs[:distinct_id] == "42" && attrs[:properties]["$session_id"] == "sess-1" && attrs[:properties][:platform] == "ios"
    end

    @backend.track("user_signed_up", actor_id: 42, properties: {platform: "ios"})
  end

  test "#track puts the event in the tenant's group" do
    Studio::Monitoring::Current.tenant_id = 7
    @client.expects(:capture).with { |attrs| attrs[:groups] == {tenant: "7"} }

    @backend.track("recipe_saved", actor_id: 42, properties: {})
  end

  test "#track without an actor or tenant sends a personless event with no group" do
    @client.expects(:capture).with { |attrs|
      !attrs.key?(:distinct_id) && !attrs.key?(:groups) && !attrs[:properties].key?("$session_id")
    }

    @backend.track("share_viewed", actor_id: nil, properties: {})
  end

  test "#track does nothing when PostHog is not initialized" do
    backend = Studio::Monitoring::Analytics::Backends::Posthog.new

    assert_nil backend.track("user_signed_up", actor_id: 42, properties: {})
  end

  test "#track_llm_generation sends $ai_generation with usage and no prompt or response" do
    @client.expects(:capture).with do |attrs|
      properties = attrs[:properties]
      attrs[:event] == "$ai_generation" &&
        attrs[:distinct_id] == "42" &&
        properties["$ai_model"] == "claude-haiku-5-5" &&
        properties["$ai_provider"] == "anthropic" &&
        properties["$ai_input_tokens"] == 1200 &&
        (properties["$ai_latency"] * 1000).round == 1500 &&
        properties["$ai_trace_id"].present? &&
        !properties.key?("$ai_input") && !properties.key?("$ai_output_choices")
    end

    @backend.track_llm_generation(**generation)
  end

  test "#track_llm_generation groups a request's calls into one trace linked to the browser session" do
    Studio::Monitoring::Current.request_id = "req-1"
    Studio::Monitoring::Current.analytics_session_id = "sess-1"
    @client.expects(:capture).with do |attrs|
      properties = attrs[:properties]
      properties["$ai_trace_id"] == "req-1" && properties["$ai_session_id"] == "sess-1" && properties["$session_id"] == "sess-1"
    end

    @backend.track_llm_generation(**generation)
  end

  private

  def generation
    {actor_id: 42, kind: "recipe_extraction", model: "claude-haiku-5-5", ok: true, error_code: nil,
     duration_ms: 1500, input_tokens: 1200, output_tokens: 300, cache_read_tokens: 0, cache_write_tokens: 0}
  end
end
