# studio-monitoring

One `Studio::Monitoring` API for studio Rails apps, set up the studio way:

- `Studio::Monitoring::Logging` sends logfmt event lines to Rails, AppSignal and PostHog Logs
- `Studio::Monitoring::Errors` reports handled errors through `Rails.error`
- `Studio::Monitoring::Metrics` records counters and durations through OpenTelemetry
- `Studio::Monitoring::Analytics` tracks product events and identifies people in PostHog

The gem's Railtie also does the setup each app used to copy:

- OpenTelemetry: traces, logs and metrics go to PostHog with 25% of traces sampled, or traces go to a local Jaeger in development; it's off otherwise
- lograge turns each request into one `http_request` line
- each app job logs one `job_performed` line
- PostHog client and posthog-rails exception capture
- request id, job id and the posthog-js session id, set for every request and job
- one `monitoring_configured` line at boot that lists what is on

## Setup

```ruby
# config/initializers/monitoring.rb
Studio::Monitoring.configure do |c|
  c.service_name = "belly"

  if (posthog = AppSettings.posthog)
    c.posthog_project token: posthog.public_project_token, host: posthog.server_host
  end

  c.actor_id = -> { Current.user&.id }
  c.tenant_id = -> { Current.space&.id }
  c.default_properties = -> { {platform: Current.platform} }

  c.untraced_paths += ["/login-link", %r{\A/[^/]+/magic_link/}]
  c.analytics_backends += [:database]
end
```

| Setting | Meaning |
| --- | --- |
| `service_name` | Required. Names the OpenTelemetry service, meter and logger |
| `posthog_project` | PostHog token and host. Not called means PostHog is off |
| `actor_id` | Who is acting. Sent as `actor_id` everywhere; the PostHog distinct id |
| `tenant_id` | Which tenant (shop, space) the work is for. Sent as `tenant_id` everywhere; the PostHog `tenant` group |
| `default_properties` | App-specific extras added to every log line, error and analytics event |
| `untraced_paths` | Path prefixes or Regexps never traced; defaults to assets and Active Storage. URLs with `token=` are never traced |
| `unlogged_actions` | `Controller#action`s with no request line |
| `log_backends` | Names from `:rails`, `:appsignal`, `:posthog`. Defaults to all three |
| `analytics_backends` | Names from `:posthog`, `:database`. Defaults to `[:posthog]` |

## Backends

Every backend ships with the gem, and apps pick backends by name. An unknown name raises at boot. To add a new backend, add it to toolshed so every app gets the same one.

If an analytics backend raises, the error is logged and the other backends still run.

`:database` writes each event to an `analytics_events` table (`actor_id`, `tenant_id`, `event_name`, `properties`, `created_at`) through `Studio::Monitoring::AnalyticsEvent`. It keeps events for 60 days:

```sh
bin/rails g studio:monitoring:analytics_events && bin/rails db:migrate
```

```yaml
# config/recurring.yml
purge_analytics_events:
  class: Studio::Monitoring::PurgeAnalyticsEventsJob
  schedule: every day at 4am
```

## Use

```ruby
Studio::Monitoring::Logging.log_warn(self, "billing_checkout_return", properties: {success: false, message: "session_not_complete"})
Studio::Monitoring::Errors.report(error, context: {url: url})
Studio::Monitoring::Metrics.increment_counter("recipe_url_import", tags: {ok: true})
Studio::Monitoring::Metrics.record_duration("recipe_url_import.duration", duration_ms, tags: {ok: true})
Studio::Monitoring::Analytics.track("recipe_saved", properties: {recipe_id: recipe.id})
Studio::Monitoring::Analytics.identify(properties: {timezone: user.timezone})
```

Event and metric names describe the flow in snake_case, object first. Never use prose for them: dashboards filter on these names.
