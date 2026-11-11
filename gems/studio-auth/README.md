# studio-auth

Passwordless sign-in for studio Rails apps: a 6-digit email code, expiring
database sessions, the staff flag, and lockout mail.

## Rules

| | |
| --- | --- |
| Code | 6 digits, valid 10 minutes, single use, 5 attempts. One resend per 60 seconds |
| Lockout | 10 wrong codes in 24 hours pause sign-in for 1 hour, plus 1 hour per further wrong code. A known device counts only its own wrong codes |
| Limits | 10 code requests an hour per account (a known device has its own 10), 30 an hour per IP (per /64 for IPv6), also counted in the database |
| Unknown address | Same response as a real one, no mail |
| Mail | The code and the lockout notice only, text and HTML, no links but support and legal. Sent on `less_than_five_seconds` |

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

The users table needs a unique `email_address` and `created_at`; the migration
adds `staff` if it's missing. The generator also writes:

- the initializer, below
- the two sign-in pages in `app/views/studio/auth/`, with their copy in
  `config/locales/studio_auth.<locale>.yml`. Restyle and reword them freely, but
  keep the form fields and route helpers. They render inside
  `app/views/layouts/studio/auth/base.html.erb`.
- a daily `Studio::Auth::PurgeExpiredJob` in `config/recurring.yml`

Rate limits need a cache store every process shares, such as Solid Cache.

```ruby
# config/initializers/studio_auth.rb
Studio::Auth.configure do |c|
  c.app_name = "Belly"
  c.mail_from = "Belly <hello@usebelly.app>"
  c.support_email = "support@usebelly.app"
  c.mail_logo_url = "https://my.usebelly.app/mail/belly-wordmark.png" # 80px tall, shown at 40px
  c.terms_url = "https://itsusstudio.com/terms"
  c.privacy_url = "https://itsusstudio.com/privacy"
  c.session_idle_timeout = 20.years # 20.years keeps a session until sign-out
  c.session_absolute_timeout = 20.years
end
```

```ruby
class User < ApplicationRecord
  include Studio::Auth::ForUser
end

class Session < ApplicationRecord
  include Studio::Auth::ForSession
end

class Current < ActiveSupport::CurrentAttributes
  attribute :session
end

class ApplicationController < ActionController::Base
  include Studio::Auth::ForController
end

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    include Studio::Auth::ForCableConnection
  end
end
```

## Use

- `allow_unauthenticated_access only: [...]` opens actions to signed-out visitors.
- `authenticated?` and `current_user` in controllers and views.
- `start_sign_in_for(user)` after signup sends the first code.
- `store_return_path(path)` returns a visitor to `path` after sign-in.
- Override `after_sign_in(user)`, `after_authentication_path` (root by default)
  or `terminate_all_sessions` (call `super`).
- Override `can_sign_in?` on the user to shut out deleted or suspended accounts.
- Hotwire Native requests (the app's `hotwire_native_app?`) get a 401 instead of
  a redirect to sign-in.
- Routes: `login_path`, `verify_path`, and `logout_path` and
  `logout_everywhere_path`, which take DELETE (`button_to`).
- Signing out disconnects that session's Action Cable sockets; signing out
  everywhere disconnects all of the user's.
- Mail follows the user's `locale`. The gem owns the mail and flash copy (en,
  fr, nl). Restyle the mail at `layouts/studio/auth/sign_in_mailer`, and preview
  it at `/rails/mailers`.

## Staff

`users.staff` marks studio staff, whom studio-admin lets into `/admin`. It
needs an `@itsusstudio.com` address, so staff sign-in rests on the studio
Workspace inbox. App review accounts are never staff, even on the studio
domain. Grant it from the console, never a form. (Organization roles are
studio-tenancy's, not this.)

## Tests

```ruby
class ActionDispatch::IntegrationTest
  include Studio::Auth::TestHelper # sign_in_as(user), sign_out,
  # assert_requires_authentication { get path }, assert_allows_unauthenticated_access { ... }
end

class AuthenticationSecurityTest < ActionDispatch::IntegrationTest
  include Studio::Auth::SecurityTests # the gem's security checks, run against the app's own pages

  def create_authentication_user(email_address)
    create(:user, email_address: email_address)
  end
end
```

## App review accounts

App store reviewers sign in with a fixed code from credentials: at most 2
accounts, never mailed, locked only after 20 wrong codes in 24 hours. Since the
code never changes, give the account nothing worth taking: its own workspace,
demo data, no staff, no real billing.

```yaml
studio_auth:
  app_review_accounts:
    appreview@usebelly.app: "xxxxxx"
```

Alert on `authentication.app_review_account_code_rejected` and
`authentication.app_review_account_locked`.
