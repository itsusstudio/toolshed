# studio-monitoring

Events, errors, logs, metrics and analytics for studio Rails apps, built on `Rails.event`, `Rails.error`, `Rails.logger`, OpenTelemetry and PostHog.

| Module | Use it for | Ends up in |
| --- | --- | --- |
| `Events` | something happened that you will search, filter or chart (pick this over `Logs` when unsure) | logfmt line in Rails, AppSignal and PostHog logs |
| `Errors` | something failed and someone should fix it | AppSignal and PostHog error tracking |
| `Logs` | free text for someone reading the app's own log | `Rails.logger` only |
| `Metrics` | a count or duration as a time series | PostHog metrics, through OpenTelemetry |
| `Analytics` | a product action for funnels and retention | PostHog, optionally the database |

## Events

One structured line with the actor, tenant, workspace, request and job ids attached; Rails filters secrets from the payload.

```ruby
Studio::Monitoring::Events.info("recipe_url_import", success: true, recipe_id: recipe.id)
Studio::Monitoring::Events.warn("checkout_return", success: false, message: "session_not_complete")
Studio::Monitoring::Events.debug("import_parse", fields: fields.size)  # local environments only
```

Names are snake_case, object first, and dashboards filter on them, so don't rename. Add `success:`, and a short `message:` on failure.

## Errors

Every report, including Rails' own, carries the actor, tenant, workspace, request and job ids. Don't report expected outcomes like an invalid form; log an event.

```ruby
Studio::Monitoring::Errors.report(error, context: {url: url})   # after a rescue
Studio::Monitoring::Errors.handle(Stripe::Error) { charge! }   # rescue and report
Studio::Monitoring::Errors.record { import! }                  # report and re-raise
```

## Logs

Plain text, never sent to AppSignal or PostHog.

```ruby
Studio::Monitoring::Logs.info("Imported #{count} recipes")
Studio::Monitoring::Logs.debug { "Parsed #{payload.inspect}" }  # block runs only when debug is on
```

## Metrics

```ruby
Studio::Monitoring::Metrics.increment_counter("recipe_url_import", tags: {ok: true})
Studio::Monitoring::Metrics.record_duration("recipe_url_import.duration", duration_ms, tags: {ok: true})
```

Use the flow's event name, plus `.duration` for durations. Tags stay low cardinality: never ids or URLs.

## Analytics

```ruby
Studio::Monitoring::Analytics.track("recipe_saved", properties: {recipe_id: recipe.id})
Studio::Monitoring::Analytics.identify(properties: {timezone: user.timezone})      # never email or name
Studio::Monitoring::Analytics.identify_tenant(properties: {plan: "pro", seats: 4})
Studio::Monitoring::Analytics.track_llm_generation(kind: "recipe_extraction", model: model, ok: true,
  error_code: nil, duration_ms: 900, input_tokens: 1200, output_tokens: 300,
  cache_read_tokens: 0, cache_write_tokens: 0)
```

## Setup

```ruby
# config/initializers/monitoring.rb
Studio::Monitoring.configure do |c|
  c.service_name = "belly" # required; names the OpenTelemetry service

  # Turns on PostHog. posthog_browser_hosts also turns on posthog-js; its host
  # should be a reverse proxy on the app's domain.
  if (posthog = AppSettings.posthog)
    c.posthog_project token: posthog.public_project_token, host: posthog.server_host
    c.posthog_browser_hosts host: posthog.proxy_host, ui_host: posthog.ui_host
  end

  # The rest is optional.
  c.default_properties = -> { {platform: Current.platform} } # runs per event: never query
  c.untraced_paths += ["/health/"]                           # default: assets, Active Storage
  c.unlogged_actions += ["Portal::HealthController#show"]    # default: health, cable, Hotwire config
  c.posthog_masked_paths = ["/t/", "/passwords/"]            # URLs that work as keys, cut to the prefix
  c.appsignal_ignored_paths = ["/admin"]
  c.log_backends = [:rails, :appsignal, :posthog]            # the default
  c.analytics_backends = [:posthog, :database]               # default [:posthog]
end
```

```ruby
# config/initializers/filter_parameter_logging.rb
Rails.application.config.filter_parameters += Studio::Monitoring::FILTER_PARAMETERS
```

The filter list matches key names, never values, across params, payloads, error context, analytics and trace URLs. Add the app's own names after it.

Set who is acting, for which tenant and in which workspace, where the app authenticates and in any job acting for someone. They're plain ids, so events never query for them: `actor_id` is the PostHog distinct id, `tenant_id` (the studio-tenancy organization) the PostHog group, and `workspace_id` a property on every event.

```ruby
Studio::Monitoring::Current.actor_id = user.id
Studio::Monitoring::Current.tenant_id = organization.id
Studio::Monitoring::Current.workspace_id = workspace.id
```

With no code, the gem logs `http_request` per request and `job_performed` per job, records `job.queue_wait` and `job.duration`, traces requests and jobs, and logs `monitoring_configured` at boot. An in-process request, such as a boot warm-up, stays out of all of it with `Studio::Monitoring::UNRECORDED_REQUEST => true` in its Rack env.

## AppSignal request sampling

AppSignal bills per request, so the gem keeps a quarter of ordinary requests. It always keeps server errors, requests with a handled error and requests over 0.5s, and always drops 404s and `appsignal_ignored_paths`. Tell AppSignal to drop the rest:

```ruby
# config/appsignal.rb
config.ignore_namespaces = [Studio::Monitoring::RequestSampling::DROPPED_NAMESPACE]
```

## Browser analytics

With `posthog_browser_hosts` set, `studio_analytics_tag` renders posthog-js, identified as `Current.actor_id` in the `Current.tenant_id` group with `Current.workspace_id` on every event, with tracing headers that join the server's traces. Without it, the tag renders nothing.

```erb
<%# in <head> %>
<%= studio_analytics_tag(properties: {platform: "web"}) unless controller_path.start_with?("admin/") %>
```

- Privacy: URLs lose their query and hash, and `posthog_masked_paths` are cut to the prefix. Autocapture keeps no text or attributes. Session replay masks all text and inputs except inside `[data-replay-unmask]`. Passwords, one-time codes, card, email and phone fields, and `[data-replay-mask]` stay masked even there. `mailto:` and `tel:` links are blanked.
- `properties` go on every browser event: low cardinality, no personal data.
- Set `Current.actor_id` on every signed-in page. A page without one drops the browser's identity, so the next person on the device starts fresh.
- The tag carries the request's CSP nonce. Allow the browser host in `script-src` and `connect-src`.
- The stub loads PostHog's latest `array.js`, so SDK releases need no gem change. Refresh the stub in `browser_analytics.js` when PostHog changes its snippet.

## Testing

```ruby
# test/test_helper.rb
require "studio/monitoring/test_helper"

class ActiveSupport::TestCase
  include Studio::Monitoring::TestHelper # records in memory; sends nothing
end
```

```ruby
assert_event_logged "checkout_return", level: :warn, payload: {success: false} # subset match, Regexp allowed
assert_no_event_logged level: :error
assert_error_reported(Stripe::Error) { charge! }
assert_analytics_tracked "recipe_saved", actor_id: user.id, properties: {recipe_id: recipe.id}
assert_analytics_identified actor_id: user.id
assert_tenant_identified tenant_id: organization.id, properties: {plan: "pro"}
assert_no_analytics_tracked "recipe_viewed"
assert_counter_incremented "recipe_url_import", tags: {ok: true}
assert_duration_recorded "recipe_url_import.duration"
```

- Pass a block to any assertion to count only what the block did.
- `logged_events`, `tracked_analytics` and `recorded_metrics` return everything so far.
- `use_analytics_backends(:database)` writes real rows, for the rest of the test or inside a block.
- Payload names matching the filter list are hidden: anything containing `_key`, `email` or `address`, or ending in `token`. Rename, e.g. `orphaned_groups` instead of `group_keys`.

## :database analytics backend

```sh
bin/rails g studio:monitoring:analytics_events && bin/rails db:migrate
```

```yaml
# config/recurring.yml; rows are kept 60 days
purge_analytics_events:
  class: Studio::Monitoring::PurgeAnalyticsEventsJob
  schedule: every day at 4am
```
