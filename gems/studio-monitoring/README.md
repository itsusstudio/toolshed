# studio-monitoring

Logging, errors, metrics and analytics for studio Rails apps.

## Setup

```ruby
# config/initializers/monitoring.rb
Studio::Monitoring.configure do |c|
  # Required. Names the OpenTelemetry service, meter and logger.
  c.service_name = "belly"

  # Optional. Turns on PostHog: analytics, logs, errors, traces and metrics.
  # Omit to keep PostHog off.
  if (posthog = AppSettings.posthog)
    c.posthog_project token: posthog.public_project_token, host: posthog.server_host
  end

  # Optional. Who is acting. Sent as actor_id; the PostHog distinct id.
  c.actor_id = -> { Current.user&.id }

  # Optional. Which tenant the work is for. Sent as tenant_id; the PostHog
  # tenant group.
  c.tenant_id = -> { Current.space&.id }

  # Optional. Extra properties on every log line, error and analytics event.
  c.default_properties = -> { {platform: Current.platform} }

  # Optional. Path prefixes or Regexps never traced. Defaults to assets and
  # Active Storage; URLs with token= are never traced.
  c.untraced_paths += ["/login-link", %r{\A/[^/]+/magic_link/}]

  # Optional. Controller#actions with no request log line. Defaults to health
  # checks, Active Storage redirects, cable and Hotwire Native config.
  c.unlogged_actions += ["Portal::HealthController#show"]

  # Optional. Any of :rails, :appsignal, :posthog. Default: all three.
  c.log_backends = [:rails, :appsignal, :posthog]

  # Optional. Any of :posthog, :database. Default: [:posthog].
  c.analytics_backends = [:posthog, :database]
end
```

## Use

```ruby
Studio::Monitoring::Logging.log_info(self, "checkout_return", properties: {success: true})
Studio::Monitoring::Errors.report(error, context: {url: url})
Studio::Monitoring::Metrics.increment_counter("checkout_return", tags: {ok: true})
Studio::Monitoring::Metrics.record_duration("checkout_return.duration", ms, tags: {ok: true})
Studio::Monitoring::Analytics.track("recipe_saved", properties: {recipe_id: 1})
Studio::Monitoring::Analytics.identify(properties: {timezone: "UTC"})
```

Name events in snake_case, object first. Dashboards filter on these names, so renaming one breaks them.

## :database backend

```sh
bin/rails g studio:monitoring:analytics_events && bin/rails db:migrate
```

```yaml
# config/recurring.yml
purge_analytics_events:
  class: Studio::Monitoring::PurgeAnalyticsEventsJob
  schedule: every day at 4am
```

Events are kept for 60 days.
