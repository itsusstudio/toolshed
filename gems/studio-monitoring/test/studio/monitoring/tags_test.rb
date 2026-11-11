require "test_helper"

class Studio::Monitoring::TagsTest < ActiveSupport::TestCase
  test "setting the actor, tenant, workspace and locale tags the AppSignal transaction" do
    Appsignal.expects(:add_tags).with({actor_id: 42})
    Appsignal.expects(:add_tags).with({tenant_id: 7})
    Appsignal.expects(:add_tags).with({workspace_id: 9})
    Appsignal.expects(:add_tags).with({locale: "fr"})

    Studio::Monitoring::Current.actor_id = 42
    Studio::Monitoring::Current.tenant_id = 7
    Studio::Monitoring::Current.workspace_id = 9
    Studio::Monitoring::Current.locale = :fr
  end

  test "clearing a value adds no tag" do
    Appsignal.expects(:add_tags).never

    Studio::Monitoring::Current.actor_id = nil
  end

  test "tags land on the request's root span, not the span that set them" do
    exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    provider = OpenTelemetry::SDK::Trace::TracerProvider.new
    provider.add_span_processor(OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter))
    tracer = provider.tracer("test")

    tracer.in_span("GET /jobs") do |root|
      OpenTelemetry::Instrumentation::Rack.stubs(:current_span).returns(root)
      tracer.in_span("JobsController#index") { Studio::Monitoring::Current.tenant_id = 7 }
    end

    spans = exporter.finished_spans.index_by(&:name)
    assert_equal 7, spans["GET /jobs"].attributes["tenant_id"]
    assert_nil spans["JobsController#index"].attributes["tenant_id"]
  end

  test "outside a request, tags land on the current span" do
    exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    provider = OpenTelemetry::SDK::Trace::TracerProvider.new
    provider.add_span_processor(OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter))

    provider.tracer("test").in_span("ReminderJob process") { Studio::Monitoring::Current.actor_id = "customer_3" }

    assert_equal "customer_3", exporter.finished_spans.sole.attributes["actor_id"]
  end

  test ".default_properties reports the request's locale after I18n reverts" do
    Studio::Monitoring::Current.locale = :fr

    assert_equal :fr, Studio::Monitoring.default_properties[:locale]
  end
end
