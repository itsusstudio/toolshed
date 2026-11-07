# studio-monitoring

Events, errors, logs, metrics and analytics for studio Rails apps, built on `Rails.event`, `Rails.error`, `Rails.logger`, OpenTelemetry and PostHog.

## Which one to use

| Module | Use it for | Ends up in |
| --- | --- | --- |
| `Events` | something happened that you will search, filter or chart | logfmt line in Rails, AppSignal and PostHog logs |
| `Errors` | something failed and someone should fix it | AppSignal and PostHog error tracking |
| `Logs` | free text for a person reading the app's own log output | `Rails.logger` only |
| `Metrics` | a count or duration you want as a time series | PostHog metrics, through OpenTelemetry |
| `Analytics` | a product action you want in funnels and retention | PostHog product analytics, optionally the database |

When unsure between `Events` and `Logs`, pick `Events`.

## Events

Wraps `Rails.event`. Each event becomes one structured line with the actor, tenant, request and job ids attached. Rails filters secrets out of the payload.

When: a flow ran (an import, a checkout return, a webhook), with what happened and why.

```ruby
Studio::Monitoring::Events.info("recipe_url_import", success: true, recipe_id: recipe.id)
Studio::Monitoring::Events.warn("checkout_return", success: false, message: "session_not_complete")
Studio::Monitoring::Events.error("stripe_webhook", success: false, message: error.class.name)
Studio::Monitoring::Events.debug("import_parse", fields: fields.size)  # local environments only
```

Name events in snake_case, object first. Dashboards filter on these names, so renaming one breaks them. Add `success:`, and `message:` with a short reason on failure.

## Errors

Wraps `Rails.error`. Every report, including errors Rails reports on its own, carries the actor, tenant, request and job ids.

When: you rescued an exception that someone should still look at, or you want an error tracked and re-raised.

```ruby
Studio::Monitoring::Errors.report(error, context: {url: url})       # after a rescue
Studio::Monitoring::Errors.handle(Stripe::Error) { charge! }       # rescue and report
Studio::Monitoring::Errors.record { import! }                      # report and re-raise
```

Don't report expected outcomes, like an invalid form; use an event.

## Logs

Wraps `Rails.logger`. Plain text, never sent to AppSignal or PostHog.

When: local debugging, or a note for someone tailing the logs. If you will want to search it later, use an event.

```ruby
Studio::Monitoring::Logs.info("Imported #{count} recipes")
Studio::Monitoring::Logs.debug { "Parsed #{payload.inspect}" }  # block only runs when debug is on
```

## Metrics

Counters and durations through OpenTelemetry.

When: you want a rate or a p95 over time, like "imports per minute" or "checkout latency".

```ruby
Studio::Monitoring::Metrics.increment_counter("recipe_url_import", tags: {ok: true})
Studio::Monitoring::Metrics.record_duration("recipe_url_import.duration", duration_ms, tags: {ok: true})
```

Match the event name for the same flow, and add `.duration` for durations. Tags must stay low cardinality: never ids or URLs.

## Analytics

Product analytics in PostHog, plus the database when `:database` is on.

When: a user did something you want in funnels, retention or per-tenant usage.

```ruby
Studio::Monitoring::Analytics.track("recipe_saved", properties: {recipe_id: recipe.id})
Studio::Monitoring::Analytics.identify(properties: {timezone: user.timezone})  # no email or name
Studio::Monitoring::Analytics.track_llm_generation(kind: "recipe_extraction", model: model, ok: true,
  error_code: nil, duration_ms: 900, input_tokens: 1200, output_tokens: 300,
  cache_read_tokens: 0, cache_write_tokens: 0)
```

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

  # Optional. Extra properties on every event, error and analytics event.
  # Runs for each one, so read values already in memory; never query.
  c.default_properties = -> { {platform: Current.platform} }

  # Optional. Path prefixes or Regexps never traced, for noise. Defaults to
  # assets and Active Storage. Secrets need no entry: query values and path
  # parameters named in filter_parameters are redacted from traces and logs.
  c.untraced_paths += ["/health/"]

  # Optional. Controller#actions with no request event. Defaults to health
  # checks, Active Storage redirects, cable and Hotwire Native config.
  c.unlogged_actions += ["Portal::HealthController#show"]

  # Optional. Path prefixes whose requests never reach AppSignal, such as
  # internal admin tools. Default: none.
  c.appsignal_ignored_paths = ["/admin"]

  # Optional. Any of :rails, :appsignal, :posthog. Default: all three.
  c.log_backends = [:rails, :appsignal, :posthog]

  # Optional. Any of :posthog, :database. Default: [:posthog].
  c.analytics_backends = [:posthog, :database]
end
```

Set who is acting and for which tenant once, where the app authenticates, and in any job that acts for someone. `actor_id` is the PostHog distinct id and `tenant_id` the PostHog tenant group. Both are plain ids, so events never query the database to find them.

```ruby
# app/controllers/concerns/authentication.rb, once the session is resumed
Studio::Monitoring::Current.actor_id = user.id
Studio::Monitoring::Current.tenant_id = user.space_id
```

```ruby
# config/initializers/filter_parameter_logging.rb
Rails.application.config.filter_parameters += Studio::Monitoring::FILTER_PARAMETERS
```

The studio filter list covers request params, event payloads, error context and trace URLs. Add app-specific names after it.

Without any code, the gem also logs one `http_request` event per request and one `job_performed` event per app job, traces requests and jobs, and logs `monitoring_configured` at boot listing what is on.

## AppSignal request sampling

AppSignal bills per request, so the gem keeps a quarter of ordinary requests and moves the rest into a namespace the agent drops. It always keeps server errors, requests that reported a handled error, and requests slower than 0.5s. It always drops 404s and `appsignal_ignored_paths`. Tell AppSignal to drop that namespace:

```ruby
# config/appsignal.rb
config.ignore_namespaces = [Studio::Monitoring::RequestSampling::DROPPED_NAMESPACE]
```

## Testing

```ruby
# test/test_helper.rb
require "studio/monitoring/test_helper"

class ActiveSupport::TestCase
  include Studio::Monitoring::TestHelper
end
```

Each test records events, analytics and metrics in memory, and sends no analytics to PostHog or the database. Errors use Rails' own assertion.

```ruby
# Events: payload is a subset match after filtering, Regexp values allowed
post checkout_return_path
assert_event_logged "checkout_return", level: :warn, payload: {success: false, message: "session_not_complete"}
assert_no_event_logged level: :error

# Errors
assert_error_reported(Stripe::Error) { charge! }

# Analytics
post recipes_path, params: params
assert_analytics_tracked "recipe_saved", actor_id: user.id, properties: {recipe_id: Recipe.last.id}
assert_analytics_identified actor_id: user.id
assert_no_analytics_tracked "recipe_viewed"

# Metrics
assert_counter_incremented "recipe_url_import", tags: {ok: true}
assert_duration_recorded "recipe_url_import.duration"
```

Each assertion takes an optional block, and then only counts what the block did. `logged_events`, `tracked_analytics` and `recorded_metrics` return everything so far.

For tests that need real rows, such as admin reports or system tests, `use_analytics_backends(:database)` sends analytics there for the rest of the test, or only inside a block.

Event payloads are filtered by `filter_parameters`, so property names matching the filter list are hidden: anything containing `_key`, `email` or `address`, or ending in `token`. Pick another name, such as `orphaned_groups` instead of `group_keys`.

## :database analytics backend

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
