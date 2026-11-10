# studio-auth

Passwordless sign-in for studio Rails apps: a 6-digit email code, expiring database sessions, reauthentication before sensitive actions, and new-device and lockout mail.

## Rules

| | |
|---|---|
| Code | 6 digits, 10 minutes, single use, 5 attempts. One resend per 60 seconds |
| Lockout | 10 wrong codes in 24 hours pause sign-in for 1 hour, plus 1 hour per further wrong code. A known device counts only its own wrong codes, so it still signs in |
| Limits | 10 code requests an hour per account (a known device has its own 10), 30 an hour per IP, counted per /64 for IPv6. The per-IP hour is also counted in the database, so it holds if the cache fails |
| Unknown address | Same response as a real one, no mail |
| Session | 30 days idle, 90 days total |
| Reauthentication | Fresh code when the last one is older than 15 minutes |
| Mail | Text and HTML, no links or images, sent by a job on `less_than_five_seconds` |

## Install

```ruby
git "https://github.com/itsusstudio/toolshed", branch: "main", glob: "gems/*/*.gemspec" do
  gem "studio-auth"
end
```

```sh
bin/rails generate studio:auth:install
bin/rails db:migrate
```

The users table needs a unique `email_address` column.

```ruby
# config/initializers/studio_auth.rb
Studio::Auth.configure do |c|
  c.app_name = "Belly"
  c.mail_from = "Belly <hello@usebelly.app>"
  c.support_email = "support@usebelly.app"
end
```

```ruby
class User < ApplicationRecord
  include Studio::Auth::User
end

class Session < ApplicationRecord
  include Studio::Auth::Session
end

class Current < ActiveSupport::CurrentAttributes
  attribute :session
end

class ApplicationController < ActionController::Base
  include Studio::Auth::Controller
end
```

Schedule `Studio::Auth::PurgeExpiredJob` daily in `config/recurring.yml`. Rate limits need a cache store shared by every process, such as Solid Cache.

## Use

- `allow_unauthenticated_access only: [...]` opens actions to signed-out visitors.
- `require_recent_authentication only: :destroy` asks for a fresh code first. The generator writes no pages for it: an app that uses it adds `studio/auth/reauthentications/new` and `studio/auth/reauthentication_codes/new`, e.g. as a modal.
- Override `can_sign_in?` on User to return false for accounts that must not sign in (deleted, suspended). They get decoys, and their sessions stop working.
- `authenticated?`, `current_user`, `recently_authenticated?` in controllers and views.
- `start_sign_in_for(user)` after signup sends the first code.
- Override `after_sign_in(user)` to act on a fresh sign-in, e.g. accept pending invitations.
- Picking the current organization is the app's job: set `Current.organization`, and have its setter feed `Studio::Monitoring::Current.tenant_id`.
- `Session.from_cookie(cookies)` outside controllers, e.g. Action Cable.
- Routes: `login_path`, `verify_path`, `logout_path`, `logout_everywhere_path`, `reauthentication_path`.
- The install generator writes the two sign-in pages into `app/views/studio/auth/` and their copy into `config/locales/studio_auth.<locale>.yml`. They are the app's to style and word; keep the form fields and the route helpers. A layout at `app/views/layouts/studio/auth/base.html.erb` wraps them, e.g. `<%= render template: "layouts/auth" %>`.

The gem owns the email and flash copy (en, fr, nl). Emails go out as text and HTML, with no links or images; an app restyles the HTML at `app/views/layouts/studio/auth/mailer.html.erb`. Regional locales such as fr-CA get the base language. Preview the emails at `/rails/mailers`; add `?locale=fr` for other languages.

## Review accounts

App store reviewers sign in with a fixed 6-digit code from credentials. At most 2 accounts, one per store. They never get mail, and a reviewer's typos don't lock them; 20 wrong codes in 24 hours do, since the code never changes.

A fixed code that never locks can be guessed, so a review account must be worth nothing to break into: its own workspace with demo data, no admin, no real billing, no access to anyone else's data.

```yaml
studio_auth:
  review_accounts:
    - email_address: appreview@usebelly.app
      login_code: "381904"
```

Alert on `authentication.review_account_code_rejected` and `authentication.review_account_locked`.

## Security tests

Every app runs the gem's checks against its own routes. Define `authentication_landing_path` if sign-in lands somewhere other than `root_path`:

```ruby
class AuthenticationSecurityTest < ActionDispatch::IntegrationTest
  include Studio::Auth::SecurityTests

  def create_authentication_user(email_address)
    create(:user, email_address: email_address)
  end
end
```
