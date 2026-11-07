Gem::Specification.new do |spec|
  spec.name = "studio-monitoring"
  spec.version = File.read(File.expand_path("../../VERSION", __dir__)).strip
  spec.authors = ["ITSUSSTUDIO"]
  spec.email = ["mackenzie@itsusstudio.com"]

  spec.summary = "ITSUSSTUDIO logging, errors, metrics and analytics for Rails apps"
  spec.description = "One Monitoring API (Logging, Errors, Metrics, Analytics) over AppSignal, PostHog and OpenTelemetry, set up the studio way by a Railtie."
  spec.homepage = "https://github.com/itsusstudio/toolshed/tree/main/gems/studio-monitoring"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*.rb", "lib/**/*.tt", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "railties", ">= 8.0"
  spec.add_dependency "activejob", ">= 8.0"
  spec.add_dependency "actionpack", ">= 8.0"
  spec.add_dependency "activerecord", ">= 8.0"

  spec.add_dependency "appsignal", ">= 4.10", "< 6"
  spec.add_dependency "lograge", "~> 0.15"
  spec.add_dependency "posthog-ruby", "~> 3.28"
  spec.add_dependency "posthog-rails", "~> 3.19"

  spec.add_dependency "opentelemetry-sdk", "~> 1.13"
  spec.add_dependency "opentelemetry-logs-sdk", "~> 0.8"
  spec.add_dependency "opentelemetry-metrics-sdk", "~> 0.22"
  spec.add_dependency "opentelemetry-exporter-otlp", "~> 0.37"
  spec.add_dependency "opentelemetry-exporter-otlp-logs", "~> 0.7"
  spec.add_dependency "opentelemetry-exporter-otlp-metrics", "~> 0.15"
  spec.add_dependency "opentelemetry-instrumentation-rails", "~> 0.42"
  spec.add_dependency "opentelemetry-instrumentation-pg", "~> 0.37"
  spec.add_dependency "opentelemetry-instrumentation-net_http", "~> 0.29"
end
