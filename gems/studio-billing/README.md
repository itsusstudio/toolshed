# studio-billing

Stripe billing for studio Rails apps. Each app describes what it sells in `config/billing.yml`; the gem sets up the app's Stripe account to match and checks it for drift.

## Install

```ruby
# Gemfile, inside the toolshed git block
gem "studio-billing"
```

```sh
bin/rails generate studio:billing:install              # the owner is Organization, the studio standard
bin/rails generate studio:billing:install RepairShop   # or name the model that pays
bin/rails db:migrate
```

The owner is the model that pays: the tenant, never the user. The generator adds `stripe_customer_id` (unique, built concurrently in its own migration) to its table, includes `Studio::Billing::ForOwner` in it, and writes the migration for the gem's tables, `config/initializers/studio_billing.rb`, a starter `config/billing.yml`, the `studio_billing` route (`POST /billing/webhooks`) and three jobs in `config/recurring.yml`: `ReconcileSubscriptionsJob` hourly, `CheckStripeJob` every Monday and `PurgeWebhookEventsJob` daily. Then define the owner's email address:

```ruby
class RepairShop < ApplicationRecord
  include Studio::Billing::ForOwner

  # Required. Where Stripe sends receipts and invoices; Checkout prefills it on
  # a first purchase. Raises NotImplementedError when left out.
  def billing_email_address = owner_email_address
end
```

## Setup

Every setting, with its default. Only the first three are required, plus one `c.usage` counter per limit.

```ruby
# config/initializers/studio_billing.rb
Studio::Billing.configure do |c|
  # Required. A restricted key (rk_), from credentials. Never a literal.
  c.api_key = Rails.application.credentials.dig(:stripe, :api_key)

  # Required. Pinned; the webhook endpoint is created on this version too.
  c.api_version = "2026-09-30.endive"

  # Required. Prefixes every Stripe Product: "Workbench Team".
  c.product_name = "Workbench"

  # Where Stripe sends events. Without it, sync skips the webhook endpoint.
  c.webhook_url = "https://app.useworkbench.co/billing/webhooks"

  # Signing secret for that endpoint, from credentials. The webhook route
  # refuses every event without it.
  c.webhook_secret = Rails.application.credentials.dig(:stripe, :webhook_secret)

  # Events the endpoint subscribes to. Default: Studio::Billing::Configuration::DEFAULT_WEBHOOK_EVENTS
  # (checkout, subscription lifecycle, invoice paid and failed, dispute,
  # refund, early fraud warning). The job handles exactly these.
  # c.webhook_events = [...]

  # Tags Checkout Sessions in the Dashboard. A lowercase label ending
  # in _ and 8 random letters.
  c.integration_identifier = "workbench_signup_qhzkdmwp"

  # Checkout. Leave automatic_tax off until a Stripe Tax registration
  # is active, or Stripe collects nothing and says nothing.
  c.automatic_tax = false        # default false
  c.ui_mode = "embedded_page"    # default; or "hosted_page"

  # Stripe HTTP timeouts, in seconds.
  c.open_timeout = 2             # default 2
  c.read_timeout = 10            # default 10
  c.write_timeout = 10           # default 10

  # Where the catalog lives.
  c.catalog_path = Rails.root.join("config/billing.yml")   # default

  # How long a past due subscription keeps its plan after its period ends.
  c.grace_period = 3.days        # default

  # Queue for the gem's jobs. Must be one the app's workers process; the default
  # matches the studio queues in config/queue.yml.
  c.queue = :less_than_five_minutes   # default

  # The models that pay. Owners in Stripe metadata only resolve to these.
  c.owner_classes = ["Organization"]  # default; Workbench: ["RepairShop"]

  # Required for the portal and the sync: the customer portal configuration
  # saved once in the Stripe Dashboard (Settings, Billing, Customer portal).
  # The sync manages its settings from then on.
  c.portal_configuration_id = "bpc_..."

  # How long processed webhook event IDs are kept before the daily purge.
  c.webhook_event_retention = 90.days   # default

  # Required: one counter per limit in billing.yml, or boot fails. per: :month
  # counts the calendar month in the app's time zone and gets that range;
  # leave per: out for a standing count.
  c.usage(:new_jobs, per: :month) { |shop, month| shop.job_tickets.where(created_at: month).count }
  c.usage(:texts, per: :month) { |shop, month| shop.text_messages.where(sent_at: month).count }
  c.usage(:locations) { |shop| shop.locations.count }

  # Optional. Finds the owner of a subscription made before the gem, from its
  # Stripe metadata, when neither the gem's metadata nor a known customer does.
  c.owner_from_metadata = ->(metadata) { RepairShop.find_by(id: metadata["repair_shop_id"]) }
end
```

Use a restricted key (`rk_`). The app needs write on Checkout Sessions, Customer portal, Subscriptions (account closure cancels them) and Customers (email address updates), and read on Prices, Products, Charges, Events, Customer portal configurations and Webhook endpoints (the weekly drift check). Only the key that runs `studio_billing:sync` also needs write on Products, Prices, Customer portal and Webhook endpoints.

## Catalog

Every key `config/billing.yml` takes, using Workbench's plans as the example.

```yaml
# Plan an owner falls back to with no subscription or grant. Must be a plan
# below. Without it, an owner with nothing gets no features and 0 of everything.
default_plan: free

# Optional. behavior: inclusive (default, the price shown is the price paid)
# or exclusive (tax added on top). Stripe can't change it on a price once
# created, so settle it before the first live sync. code: the Stripe product
# tax code set on every product.
tax:
  behavior: inclusive
  code: txcd_10103001

# Required. Checkout sends this on every session.
branding:
  display_name: Workbench              # required
  background_color: "#ffffff"          # required, hex
  button_color: "#1f1f1f"              # required, hex
  border_style: rounded                # optional: rectangular, rounded or pill
  font_family: inter                   # optional, a Stripe-supported font
  icon_url: https://useworkbench.co/icon.png   # optional, https, square
  logo_url: https://useworkbench.co/logo.png   # optional, https

# Optional. business_profile and features take Stripe's portal configuration
# fields. features is merged over Studio::Billing::Sync::DEFAULT_PORTAL_FEATURES,
# so list only what differs. Switchable prices are filled in by the sync.
portal:
  business_profile:
    headline: Manage your Workbench plan
    privacy_policy_url: https://useworkbench.co/privacy
    terms_of_service_url: https://useworkbench.co/terms
  features:
    customer_update:
      allowed_updates: [email, address, name, tax_id]
    subscription_cancel:
      mode: at_period_end
      cancellation_reason:
        enabled: true
        options: [too_expensive, unused, switched_service, other]
    subscription_update:
      proration_behavior: always_invoice
      schedule_at_period_end:
        conditions: [{type: decreasing_item_amount}]

# Required. In rank order, lowest first: when an owner has several plans,
# the one listed last wins.
plans:
  # No prices: free, never sent to Stripe.
  - code: free                         # required, never changes or gets reused
    name: Free                         # required
    limits:                            # every plan sets every limit
      new_jobs: 20
      texts: 0
      locations: 1

  - code: team
    name: Team
    description: For independent shops and brands   # shown on Checkout and the portal
    features: [texts, remove_branding]               # names product code asks about
    limits:
      new_jobs: 200
      texts: 250
      locations: 1
    prices:
      - lookup_key: team_yearly        # required, never changes or gets reused
        interval: year                 # month or year
        amounts:                       # whole units; first currency is the base
          CAD: 590
          USD: 430
      - lookup_key: team_monthly
        interval: month
        amounts:
          CAD: 69
          USD: 49

  - code: scale
    name: Scale
    description: For busy counters, wholesale and several stores
    features: [texts, remove_branding, several_locations]
    limits:
      new_jobs: unlimited
      texts: 1000
      locations: unlimited
    prices:
      - lookup_key: scale_yearly
        interval: year
        amounts: {CAD: 1490, USD: 1090}
      - lookup_key: scale_monthly
        interval: month
        amounts: {CAD: 179, USD: 129}

  # No longer sold; existing subscriptions keep billing on it.
  - code: simple
    name: Simple
    legacy: true                       # not offered in Checkout or the portal
    entitlements_of: team              # takes Team's features and limits, lists none
    prices:
      - lookup_key: simple_yearly_v2
        interval: year
        amounts: {CAD: 400}
```

- A plan is a tier, and a price is a cadence. Each plan with prices becomes a Stripe Product named "<product_name> <plan name>", with the plan code as its ID.
- Each price becomes one Stripe Price: the first currency is its base, the rest are currency options, so Checkout shows people their own currency.
- Amounts are in whole currency units (`590`, `69.00`) and become `Money` objects, so each currency gets its own minor unit (cents for CAD, none for JPY). An unknown currency code, or more decimal places than the currency allows, fails to load. `price.amount(:cad)` returns the `Money` for display. Stripe treats a few currencies (HUF, ISK, TWD, UGX) differently from their ISO minor units; check Stripe's currency docs before adding one.
- A plan without prices is free (`plan.free?`) and never reaches Stripe.
- Every plan sets every limit, as a whole number or `unlimited`; a plan that leaves one out fails to load. Features are the names a plan lists. Words for features and limits live in the app's locale files, and periods live with the usage counters in the initializer.
- A plan with `entitlements_of` takes another plan's features and limits and lists none of its own. That plan must have its own.
- `branding` is required: `display_name`, `background_color` and `button_color` (hex), plus optional `border_style` (rectangular, rounded or pill), `font_family`, `icon_url` and `logo_url` (https). Checkout sends it on every session as `branding_settings`, so the page matches the app whatever the account's Dashboard settings say. Receipts, invoices and the portal still use the account's branding, set by hand (below).
- `portal.features` takes Stripe's portal feature settings and overrides the defaults in `Studio::Billing::Sync::DEFAULT_PORTAL_FEATURES`. Every current plan's prices are offered for switching; legacy plans aren't.

## Keeping Stripe in step

```sh
bin/rails studio_billing:check   # read-only, exits 1 when Stripe differs
bin/rails studio_billing:sync    # makes Stripe match config/billing.yml
```

- Both print the same list of changes. Run `check` first.
- `check` compares the live account with the YAML: product names and descriptions, price amounts, currencies, intervals and tax behaviour, the portal's live settings (a change made in the Dashboard counts as drift), and the webhook endpoint's events.
- Prices are never edited. A changed amount, currency, interval or tax behaviour creates a new price, moves the lookup key to it and archives the old one. Subscriptions on the old price keep billing at the old amount.
- A price the YAML no longer lists is left alone, so removing a plan can't archive what existing customers pay.
- The sync creates the webhook endpoint with the events the gem handles, on the app's API version. Its signing secret is shown once, and only in an interactive terminal. Add it to credentials as `stripe.webhook_secret`.

## What an owner may do

Product code asks entitlements, never a plan code.

```ruby
shop.entitlements.plan                  # => the Catalog::Plan in effect
shop.entitlements.allows?(:texts)       # => true
shop.entitlements.limit(:new_jobs)      # => 200, or nil when unlimited
shop.entitlements.unlimited?(:locations)
shop.entitlements.used(:new_jobs)       # => 143, from the c.usage counter
shop.entitlements.over?(:new_jobs)      # => false; never true when unlimited
shop.entitlements.subscription          # => the Studio::Billing::Subscription that counts, or nil
```

- The plan in effect is the one listed last in `billing.yml` among: subscriptions that count (trialing, active or past due, with the period ended less than `c.grace_period` ago), active plan grants, and `default_plan`.
- A name no plan lists raises `Studio::Billing::Entitlements::UnknownNameError`, so a typo fails in tests.
- What happens past a limit is the app's choice. The gem only reports it.

## Grants

Access nobody pays Stripe for: trials, staff, partners, demos, students, comps, packs.

```ruby
shop.billing_grants.create!(reason: "trial", plan_code: "team", expires_at: 14.days.from_now)
shop.billing_grants.create!(reason: "student", plan_code: "team", expires_at: Date.new(2027, 6, 30))
shop.billing_grants.create!(reason: "text_pack", limit_name: "texts", quantity: 500, granted_by: current_user)
grant.revoke!
```

- A grant gives either a plan or a quantity added to one limit, never both. Plan and limit names must be in `billing.yml`.
- A grant counts from `starts_at` (now when empty) until `expires_at` (forever when empty) or until it's revoked.
- `reason` is the app's own word; `granted_by` and `note` are for the audit trail.

## Checkout and the portal

```ruby
session = Studio::Billing::Checkout.new.create_session(
  owner: shop, lookup_key: "team_yearly",
  return_url: billing_return_url(session_id: "{CHECKOUT_SESSION_ID}")
)
# embedded_page: hand session.client_secret to Stripe.js. hosted_page: redirect to session.url.

completion = Studio::Billing::Checkout.new.complete(session_id: params[:session_id])
completion.complete?        # the subscription and customer are recorded

Studio::Billing::Portal.new.create_session(owner: shop, return_url: billing_url).url
Studio::Billing::Portal.new.create_session(owner: shop, return_url: billing_url,
  flow: :subscription_cancel, after_completion_url: billing_url).url
```

- Checkout reuses the owner's Stripe customer, puts the owner in the session and subscription metadata, sends the catalog's branding, and never sets payment methods (the Dashboard does).
- It raises `Checkout::NotForSaleError` for a legacy or unknown price and `Checkout::AlreadySubscribedError` for an owner with a subscription that counts.
- Portal flows: `payment_method_update`, `subscription_cancel`, `subscription_update`. It raises `Portal::NoCustomerError` for an owner who has never paid.
- Access follows the recorded subscription, never the return page alone.

## Keeping the Stripe customer current

The owner's email address goes to Stripe on the first purchase only. When it changes, call:

```ruby
shop.update_stripe_email_address   # sends billing_email_address to the Stripe customer; no-op before the first purchase
```

Call it from the app's email address change flow, not a callback.

## Closing an account

Stripe keeps charging until the subscription is cancelled, and it never hears that an account was deleted. Call `cancel_billing!` in the app's account closure flow, where the person asks to close, not at the final purge:

```ruby
shop.cancel_billing!                       # cancel now, no refund, revoke grants
shop.cancel_billing!(at_period_end: true)  # stop renewing; access until the paid period ends
```

- It cancels every subscription that hasn't ended and records Stripe's answer. A subscription Stripe already cancelled isn't an error, so calling it twice is safe.
- Refunds are a person's decision in the Stripe Dashboard, never the gem's.
- Deleting an owner whose subscription would charge again (not ended, no `cancel_at`) raises `Studio::Billing::BillingStillActiveError` and deletes nothing. A flow that forgets `cancel_billing!` fails loudly in development and tests.
- When Stripe later ends a cancelled subscription for an owner that's gone, the event is skipped quietly.

## Staying in sync with Stripe

Every path re-fetches the subscription from Stripe and upserts one row per Stripe subscription, so an event that arrives late or twice can't leave stale state.

| When | What runs |
| --- | --- |
| Return from Checkout | `Checkout#complete` |
| Stripe sends an event | `POST /billing/webhooks` checks the signature (400 when bad) and queues `Studio::Billing::ProcessStripeWebhookJob`; the job handles each event ID once |
| Every hour | `Studio::Billing::ReconcileSubscriptionsJob` reads subscription events since its last run and syncs each subscription they name |
| By hand | `bin/rails studio_billing:reconcile_all` syncs every subscription and resets the hourly cursor |

- Disputes, refunds and early fraud warnings don't change a subscription in Stripe. The job reports them to `Rails.error` as warnings and publishes `studio_billing.payment_problem`.
- The hourly job raises `Reconciler::CursorExpiredError` if its last run is older than Stripe's 30 days of events. Run `reconcile_all` to recover.
- A subscription whose owner can't be found is reported and skipped.
- Every Monday `CheckStripeJob` runs the same comparison as `studio_billing:check` against the live account and reports any drift to `Rails.error` as a warning, listing each difference.
- `check` and `sync` also note active prices on the gem's products with no lookup key in `billing.yml`, like an old price left active by an interrupted change. They're noted, not archived: archive one in the Dashboard once no subscription uses it.
- Every day `PurgeWebhookEventsJob` deletes processed webhook event IDs older than `c.webhook_event_retention`.

The owner is found from the gem's metadata, then a Stripe customer the gem has seen, then `c.owner_from_metadata`.

### Reacting in the app

```ruby
ActiveSupport::Notifications.subscribe("studio_billing.subscription_changed") do |event|
  event.payload => {owner:, subscription:, plan_before:, plan_after:}
end

ActiveSupport::Notifications.subscribe("studio_billing.payment_problem") do |event|
  event.payload => {owner:, event_type:, stripe_object_id:, stripe_charge_id:}
end
```

The app never handles a Stripe event itself. Notifications are sent after the gem's own writes commit, and a webhook that fails is retried, so a subscriber can run more than once for the same change: make subscribers safe to repeat.

The webhook job receives only the Stripe event ID and fetches the event from Stripe, so no customer details are stored in job arguments.

## Tables

| Table | Holds |
| --- | --- |
| owner's `stripe_customer_id` | The owner's Stripe customer, on the owner's own table |
| `billing_subscriptions` | One row per Stripe subscription: status, price, lookup key, plan, period end, `cancel_at` |
| `billing_grants` | Plan and limit grants |
| `billing_sync_cursors` | The hourly job's last event |
| `billing_webhook_events` | Processed event IDs and their owner, kept 90 days |

## By hand, once per account

Stripe has no API for these on your own account:

1. Create the account under the studio Organization, and a sandbox for it.
2. Customer portal: open Settings, Billing, Customer portal and save it once, then copy its configuration ID (`bpc_...`) into `c.portal_configuration_id`. Until then `check` reports a by-hand step and portal sessions raise.
3. Activate it: business details and bank account.
4. Public details: statement descriptor (the product's domain in capitals, like `USEWORKBENCH.CO`), support email and website.
5. Branding: icon, logo and colours. Receipts, invoices and the portal use them.
6. Failed payments: turn on Smart Retries, and cancel the subscription when every retry fails.
7. Customer emails: receipts and refunds on.
8. A restricted key per environment, in that environment's credentials.
