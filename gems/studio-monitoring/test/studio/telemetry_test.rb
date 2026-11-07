require "test_helper"

class Studio::Monitoring::TelemetryTest < ActiveSupport::TestCase
  OTEL_KEYS = ["OTEL_EXPORTER_OTLP_ENDPOINT", "OTEL_EXPORTER_OTLP_HEADERS", "OTEL_TRACES_SAMPLER", "OTEL_TRACES_SAMPLER_ARG", "OTEL_LOGS_EXPORTER", "OTEL_METRICS_EXPORTER", "OTEL_SDK_DISABLED"].freeze

  setup do
    @saved_env = OTEL_KEYS.to_h { |key| [key, ENV.delete(key)] }
    @config = Studio::Monitoring::Configuration.new
    @config.service_name = "dummy"
  end

  teardown do
    @saved_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "untraced requests cover default paths, app paths and any token in the query" do
    untraced = Studio::Monitoring::Telemetry.untraced_requests(@config.untraced_paths + ["/login-link", %r{\A/[^/]+/magic_link/}])

    assert untraced.call(rack_env("/assets/app.css"))
    assert untraced.call(rack_env("/rails/active_storage/blobs/redirect/abc"))
    assert untraced.call(rack_env("/login-link/abc"))
    assert untraced.call(rack_env("/acme-shop/magic_link/abc"))
    assert_not untraced.call(rack_env("/recipes"))
  end

  test "with a PostHog project, OpenTelemetry exports to it at 25% of traces" do
    @config.posthog_project(token: "phc_1", host: "https://us.i.posthog.com")
    Studio::Monitoring::Telemetry.stubs(:configure_sdk)

    Studio::Monitoring::Telemetry.setup(@config, env: ActiveSupport::EnvironmentInquirer.new("production"))

    assert_equal "https://us.i.posthog.com/i", ENV["OTEL_EXPORTER_OTLP_ENDPOINT"]
    assert_equal "Authorization=Bearer phc_1", ENV["OTEL_EXPORTER_OTLP_HEADERS"]
    assert_equal "0.25", ENV["OTEL_TRACES_SAMPLER_ARG"]
  end

  test "an OTEL env var set on the host wins over the default" do
    @config.posthog_project(token: "phc_1", host: "https://us.i.posthog.com")
    ENV["OTEL_TRACES_SAMPLER_ARG"] = "1.0"
    Studio::Monitoring::Telemetry.stubs(:configure_sdk)

    Studio::Monitoring::Telemetry.setup(@config, env: ActiveSupport::EnvironmentInquirer.new("production"))

    assert_equal "1.0", ENV["OTEL_TRACES_SAMPLER_ARG"]
  end

  test "development without PostHog sends traces only" do
    Studio::Monitoring::Telemetry.stubs(:configure_sdk)

    Studio::Monitoring::Telemetry.setup(@config, env: ActiveSupport::EnvironmentInquirer.new("development"))

    assert_equal "none", ENV["OTEL_LOGS_EXPORTER"]
    assert_equal "none", ENV["OTEL_METRICS_EXPORTER"]
    assert Studio::Monitoring::Telemetry.enabled?
  end

  test "other environments without PostHog turn OpenTelemetry off" do
    Studio::Monitoring::Telemetry.expects(:configure_sdk).never

    Studio::Monitoring::Telemetry.setup(@config, env: ActiveSupport::EnvironmentInquirer.new("staging"))

    assert_not Studio::Monitoring::Telemetry.enabled?
  end

  private

  def rack_env(path, query = "")
    {"PATH_INFO" => path, "QUERY_STRING" => query}
  end
end
