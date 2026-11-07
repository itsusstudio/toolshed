require "test_helper"

class Studio::Monitoring::MetricsTest < ActiveSupport::TestCase
  setup do
    @exporter = OpenTelemetry::SDK::Metrics::Export::InMemoryMetricPullExporter.new
    provider = OpenTelemetry::SDK::Metrics::MeterProvider.new
    provider.add_metric_reader(@exporter)
    Studio::Monitoring::Metrics.stubs(:meter).returns(provider.meter("test"))
  end

  test ".increment_counter counts by tag, dropping nil tags so they do not split the series" do
    Studio::Monitoring::Metrics.increment_counter("recipe_url_import", tags: {ok: true, error_code: nil})
    Studio::Monitoring::Metrics.increment_counter("recipe_url_import", tags: {ok: true})

    point = only_data_point("recipe_url_import")
    assert_equal({"ok" => "true"}, point.attributes)
    assert_equal 2, point.value
  end

  test ".record_duration records milliseconds into a histogram" do
    Studio::Monitoring::Metrics.record_duration("recipe_url_import.duration", 900, tags: {ok: false})
    Studio::Monitoring::Metrics.record_duration("recipe_url_import.duration", 100, tags: {ok: false})

    point = only_data_point("recipe_url_import.duration")
    assert_equal({"ok" => "false"}, point.attributes)
    assert_equal 2, point.count
    assert_equal 1000, point.sum
  end

  test "metrics are a no-op when OpenTelemetry is not configured, as in test" do
    Studio::Monitoring::Metrics.unstub(:meter)

    assert_nil Studio::Monitoring::Metrics.increment_counter("recipe_url_import", tags: {ok: true})
  end

  private

  def only_data_point(name)
    @exporter.pull
    metric = @exporter.metric_snapshots.find { |snapshot| snapshot.name == name }
    assert_equal 1, metric.data_points.size, "expected one series for #{name}"
    metric.data_points.first
  end
end
