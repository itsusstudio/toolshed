require "test_helper"

class Studio::Monitoring::ErrorContextTest < ActiveSupport::TestCase
  class Recorder
    attr_reader :contexts

    def initialize
      @contexts = []
    end

    def report(_error, context:, **)
      @contexts << context
    end
  end

  setup do
    @recorder = Recorder.new
    Rails.error.subscribe(@recorder)
  end

  teardown { Rails.error.unsubscribe(@recorder) }

  test "every Rails.error report carries the actor, tenant and request id" do
    Studio::Monitoring::Current.actor_id = 42
    Studio::Monitoring::Current.tenant_id = 7
    Studio::Monitoring::Current.request_id = "req-1"

    Rails.error.report(StandardError.new("boom"))

    assert_equal({actor_id: 42, tenant_id: 7, request_id: "req-1"}, @recorder.contexts.sole.slice(:actor_id, :tenant_id, :request_id))
  end

  test "context is filtered, including controller params" do
    params = ActionController::Parameters.new(full_name: "Jo Bloggs", email_address: "jo@example.com", note: "kept")

    Rails.error.report(StandardError.new("boom"), context: {params: params, phone: "555"})

    context = @recorder.contexts.sole
    assert_equal({"full_name" => "[FILTERED]", "email_address" => "[FILTERED]", "note" => "kept"}, context[:params])
    assert_equal "[FILTERED]", context[:phone]
  end

  test "the caller's context wins over the defaults" do
    Studio::Monitoring::Current.actor_id = 42

    Rails.error.report(StandardError.new("boom"), context: {actor_id: 1, url: "https://example.com"})

    assert_equal({actor_id: 1, url: "https://example.com"}, @recorder.contexts.sole.slice(:actor_id, :url))
  end

  test "errors Rails reports itself get the context too" do
    Studio::Monitoring::Current.actor_id = 42

    Rails.error.handle { raise "boom" }

    assert_equal 42, @recorder.contexts.sole[:actor_id]
  end
end
