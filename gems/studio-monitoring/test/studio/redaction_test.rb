require "test_helper"

class Studio::Monitoring::RedactionTest < ActionDispatch::IntegrationTest
  Redaction = Studio::Monitoring::Redaction

  test ".masked_path is the route pattern when a path parameter is sensitive" do
    get "/t/abc123secret"

    assert_equal "/t/:token", Redaction.masked_path(request)
  end

  test ".masked_path is nil for routes without sensitive parameters" do
    get "/recipes/123"

    assert_nil Redaction.masked_path(request)
  end

  test ".filter_query filters sensitive values and keeps the rest" do
    assert_equal "token=[FILTERED]&page=2&api_key=[FILTERED]&flag",
      Redaction.filter_query("token=abc&page=2&api_key=xyz&flag")
  end

  test "the query span processor filters url.query when a span starts" do
    span = mock("span")
    span.stubs(:attributes).returns({"url.query" => "token=abc&page=2"})
    span.expects(:set_attribute).with("url.query", "token=[FILTERED]&page=2")

    Redaction::QuerySpanProcessor.new.on_start(span, nil)
  end

  test "the query span processor redacts real SDK spans before export" do
    exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    provider = OpenTelemetry::SDK::Trace::TracerProvider.new
    provider.add_span_processor(Redaction::QuerySpanProcessor.new)
    provider.add_span_processor(OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter))

    provider.tracer("test").in_span("GET", attributes: {"url.query" => "token=abc"}) {}

    assert_equal "token=[FILTERED]", exporter.finished_spans.sole.attributes["url.query"]
  end

  test "the query span processor leaves spans without a query alone" do
    span = mock("span")
    span.stubs(:attributes).returns({"url.path" => "/recipes"})
    span.expects(:set_attribute).never

    Redaction::QuerySpanProcessor.new.on_start(span, nil)
  end

  test "requests to a sensitive route record the route pattern on the request span" do
    span = mock("span")
    span.stubs(:recording?).returns(true)
    span.expects(:set_attribute).with("url.path", "/t/:token")
    OpenTelemetry::Instrumentation::Rack.stubs(:current_span).returns(span)

    get "/t/abc123secret"
  end

  test "the request log line carries the route pattern instead of the token" do
    request = ActionDispatch::Request.new(Rack::MockRequest.env_for("/t/abc123secret"))
    request.stubs(:route_uri_pattern).returns("/t/:token(.:format)")
    request.stubs(:path_parameters).returns({token: "abc123secret"})
    event = ActiveSupport::Notifications::Event.new("process_action.action_controller", 0, 1, "id", {request: request})

    options = DummyApp.config.lograge.custom_options.call(event)

    assert_equal "/t/:token", options[:path]
  end
end
