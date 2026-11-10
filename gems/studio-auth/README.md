# studio-auth

Passwordless sign-in for studio Rails apps: a 6-digit email code, expiring
database sessions, and new-device and lockout mail.

## Rules

|                 |                                                                                                                                                                                                    |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Code            | 6 digits, 10 minutes, single use, 5 attempts. One resend per 60 seconds                                                                                                                            |
| Lockout         | 10 wrong codes in 24 hours pause sign-in for 1 hour, plus 1 hour per further wrong code. A known device counts only its own wrong codes, so it still signs in                                      |
| Limits          | 10 code requests an hour per account (a known device has its own 10), 30 an hour per IP, counted per /64 for IPv6. The per-IP hour is also counted in the database, so it holds if the cache fails |
| Unknown address | Same response as a real one, no mail                                                                                                                                                               |
| Session | Set per app: an idle limit (unused this long) and an absolute limit (this long after sign-in). `20.years` keeps a session until sign-out |
| Mail | Text and HTML, no sign-in links; the only links are the support address and legal pages. Sent by a job on `less_than_five_seconds` |

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

The users table needs a unique `email_address` and `created_at`.

The generator writes the two sign-in pages into `app/views/studio/auth/` and
their copy into `config/locales/studio_auth.<locale>.yml`. They are the app's to
style and word; keep the form fields and the route helpers. A layout at
`app/views/layouts/studio/auth/base.html.erb` wraps them, e.g.
`<%= render template: "layouts/auth" %>`.

```ruby
# config/initializers/studio_auth.rb
Studio::Auth.configure do |c|
  c.app_name = "Belly"
  c.mail_from = "Belly <hello@usebelly.app>"
  c.support_email = "support@usebelly.app"
  c.mail_logo_url = "https://my.usebelly.app/mail/belly-wordmark.png"
  c.terms_url = "https://itsusstudio.com/terms"
  c.privacy_url = "https://itsusstudio.com/privacy"
  c.session_idle_timeout = 20.years
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
```

The generator also schedules `Studio::Auth::PurgeExpiredJob` daily in
`config/recurring.yml`, on the `less_than_five_hours` queue; move it to a
quieter hour if needed. Rate limits need a cache store shared by every process,
such as Solid Cache.

## Use

Controllers

- `allow_unauthenticated_access only: [...]` opens actions to signed-out
  visitors.
- `authenticated?` and `current_user` in controllers and views.
- `start_sign_in_for(user)` after signup sends the first code.
- `remember_return_to(path)` brings a visitor back to `path` after they sign in.
- Override `after_sign_in(user)` to act on a fresh sign-in, e.g. accept
  invitations.
- Override `after_authentication_path` to land somewhere other than root.
- Override `terminate_all_sessions` (calling `super`) to end anything else a
  session holds open, such as Action Cable connections.
- Hotwire Native requests get a 401 instead of a redirect, so the shell can show
  its own sign-in screen. The gem detects them through the app's
  `hotwire_native_app?`.

Users

- The mails read `locale` and `time_zone` from the user when it has them, so a
  new sign-in shows the user's own time; without a zone it shows UTC.
- Override `can_sign_in?` to return false for accounts that must not sign in
  (deleted, suspended). They get decoys, and their sessions stop working.
- `Session.from_cookie(cookies)` outside controllers, e.g. Action Cable or a
  route constraint.

Routes

- `login_path`, `verify_path`, `logout_path`, `logout_everywhere_path`. The
  logout routes take DELETE, so use `button_to`.

`c.terms_url` and `c.privacy_url` are linked from the mail footer.
`c.mail_logo_url` is the full URL of the app's logo, hosted on the
app's own domain, shown at the top of the HTML mail. Export it at twice its 40px
display height so it stays sharp.

The gem owns the email and flash copy (en, fr, nl). Emails go out as text and
HTML; an app restyles the HTML at
`app/views/layouts/studio/auth/mailer.html.erb`. Regional locales such as fr-CA
get the base language. Preview the emails at `/rails/mailers`; add `?locale=fr`
for other languages.

## App review accounts

App store reviewers sign in with a fixed 6-digit code from credentials. At most
2 accounts, one per store. They never get mail, and a reviewer's typos don't
lock them; 20 wrong codes in 24 hours do, since the code never changes.

A fixed code that never locks can be guessed, so an app review account must be worth
nothing to break into: its own workspace with demo data, no admin, no real
billing, no access to anyone else's data.

```yaml
studio_auth:
  app_review_accounts:
    appreview@usebelly.app: "xxxxxx"
```

Alert on `authentication.app_review_account_code_rejected` and
`authentication.app_review_account_locked`.

## Security tests

The gem ships its security checks as tests for each app to include. Run inside
the app, they cover its own pages, layouts, controllers and middleware, so a
restyled page or a new filter can't quietly undo a protection, for example by
revealing whether an email has an account:

```ruby
class AuthenticationSecurityTest < ActionDispatch::IntegrationTest
  include Studio::Auth::SecurityTests

  def create_authentication_user(email_address)
    create(:user, email_address: email_address)
  end
end
```
