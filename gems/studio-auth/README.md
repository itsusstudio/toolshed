# studio-auth

Passwordless sign-in and sign-up for studio Rails apps: a 6-digit email code,
expiring database sessions, the staff flag, and lockout mail.

## Rules

| | |
| --- | --- |
| Code | 6 digits, valid 10 minutes, single use, 5 attempts. Asking again from the same browser within 60 seconds returns the same code, except "Send a new code", which mails a fresh one and ends the old one. The mail budget is the only brake on it |
| Lockout | 10 wrong codes in 24 hours pause sign-in for 1 hour, plus 1 hour per further wrong code. A known device counts only its own wrong codes |
| Limits | 5 code requests an hour per address (a known device has its own 5), 30 an hour per IP (per /64 for IPv6), also counted in the database |
| Unknown address | No mail. The signup page opens with the address filled in and a line saying there's no account for it yet, so a typo shows. Sign-up codes come only from the signup page |
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
- a daily `Studio::Auth::PurgeExpiredJob` in `config/recurring.yml`

Rate limits need a cache store every process shares, such as Solid Cache.

```ruby
# config/initializers/studio_auth.rb
Studio::Auth.configure do |c|
  c.app_name = "Belly"
  c.mail_from = "Belly <hello@usebelly.app>"
  c.wordmark_style = "sans" # the app name's voice: "serif" or "sans"
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

## Upgrading

Login codes are keyed by email address. An app installed before that adds the
column and drops `user_id` once the new code is deployed:

```ruby
add_column :studio_auth_login_codes, :email_address, :string
add_index :studio_auth_login_codes, [:email_address, :created_at], algorithm: :concurrently
```

Invitations need the `studio_auth_invitations` table, and pending sign-ups the
`studio_auth_pending_sign_ups` table. Copy each `create_table` from the install
template into a migration.

## Sign-in pages and mail

The gem owns the sign-in and code pages and the sign-in mail: markup, copy
(en, fr, nl) and the server logic behind them. They're built from
[Uniform](https://github.com/itsusstudio/uniform) and nothing else: the pages
sit in `u-auth-shell`, the code field is `<u-input-code submit>`, and the mail
uses Uniform's layout and blocks. The gem ships no CSS, JavaScript or logo.
Every studio app shows the same pages and mail. The app supplies only:

- its name, set as a Uniform wordmark in the voice `c.wordmark_style` names
- a blurb under the name, as `studio_auth.blurb` in its own locale files
  (optional)
- a Uniform document layout at `app/views/layouts/uniform.html.erb`, the
  studio's name for it, that links Uniform's
  stylesheets and renders the gem's page block in its body:
  `<%= content_for?(:studio_auth_page) ? yield(:studio_auth_page) : yield %>`
  (the gem also sets `content_for :page_title`)

The sign-in page shows "Don't have an account? Create one" under the email
field, linked to the gem's signup page, unless sign-up is off.

App pages can use the same frame with `layout "studio/auth"`.

Don't copy the gem's views into the app: a view at the same path overrides
the gem's and the pages drift apart again. Reword through the app's own
locale files (`studio_auth.codes.new.title`, ...) only where a locale needs it.

## Use

- `allow_unauthenticated_access only: [...]` opens actions to signed-out visitors.
- `authenticated?` and `current_user` in controllers and views.
- Sign-up is the gem's: `/signup` asks for a full name and an email address,
  carries the browser's time zone, and mails a code. Nothing is written to
  `users` before the code checks out. An address that already has an account
  just signs in.
- Once the code checks out, the sign-up waits in `studio_auth_pending_sign_ups`
  for 30 days. The browser that verified gets a signed cookie for it that
  lasts 1 hour and ends on sign-in or sign-out, because finishing setup signs
  the person in. After that, typing the address on the sign-in page again, on
  any browser, mails a code and carries on.
- An app that needs a tenant or settings before the user exists names its
  setup page in the initializer: `c.finish_sign_up_path = :setup_path`. Its
  setup screen reads `pending_sign_up`
  (`email_address`, `full_name`, `time_zone`), creates the user and tenant
  together and calls `finish_sign_up(user)`, which signs them in.
- An app with no setup leaves it nil. The gem then creates the user with
  `email_address` and `full_name` and calls `prepare_new_user(user)` before
  the save, for the app's defaults. The `users` table needs `full_name`.
- Override `after_sign_up(user)` for where a new user goes next
  (`after_authentication_path` by default).
- `start_sign_in_for(user)` mails a code to an existing user.
- `store_return_path(path)` returns a visitor to `path` after sign-in.
- `request_reauthentication(return_to: path, **flash)` sends a signed-in user to
  the sign-in page with their address filled in, then to `path`. The session
  stays, so leaving the page leaves them signed in.
- Override `after_sign_in(user)`, `after_authentication_path` (root by default)
  or `terminate_all_sessions` (call `super`).
- Override `can_sign_in?` on the user to shut out deleted or suspended accounts.
  By default a user with no email address can't sign in.
- Override `requires_email_address?` to let users who never sign in, like a
  team member without a login, leave `email_address` blank. Their column must
  allow NULL.
- Hotwire Native requests (the app's `hotwire_native_app?`) get a 401 instead of
  a redirect to sign-in.
- Routes: `login_path`, `verify_path`, and `logout_path` and
  `logout_everywhere_path`, which take DELETE (`button_to`).
- Signing out disconnects that session's Action Cable sockets; signing out
  everywhere disconnects all of the user's.
- Mail follows the user's `locale`. The gem owns the mail and flash copy (en,
  fr, nl). Restyle the mail at `layouts/studio/auth/sign_in_mailer`, and preview
  it at `/rails/mailers`.

## Changing an email address

The gem owns the whole change, with codes like sign-in, never links. Link to
`change_email_address_path` from the app's account settings and set
`c.account_settings_path` (a path helper, like `:settings_profile_path`) so the
flow returns there. Nil returns to the root.

1. The person types the new address. It's refused before any mail if it's the
   same address, another account's, undeliverable, or not on the studio domain
   for staff.
2. A browser that signed in, or proved itself, in the last 10 minutes goes
   straight to step 3. Any other first gets a code at the current address,
   because sessions last for years and a shared counter device stays signed in.
3. A code goes to the new address. When it checks out, the address changes,
   the old address's live codes end, any pending sign-up for the new address
   is deleted, and the old address gets a security alert naming the new one,
   the device and the time.

Sessions stay signed in. The alert names `c.support_email_address`, and sets
it as Reply-To, when the app sets one. Codes share the sign-in limits for each
address, so the change can't be used to mail an inbox more than sign-in can.
App review accounts can't change their address.

## Invitations

An invite gives an existing user without a login an email address and signs
them in. The app creates the user first (a team member it can already assign
work to), then calls:

```ruby
Studio::Auth::Invitation.invite!(user: member, email_address: "dana@example.com", invited_by: current_user)
member.open_invitation&.revoke!
```

- `invite!` replaces any open invite for that user and mails a link to
  `/invites/:token`. Only the token's digest is stored. Links work 7 days.
- Opening the link proves the inbox: one button sets the user's
  `email_address`, marks the invite accepted and signs them in.
- The mail and page say who invited them, where, and as what. Define
  `invitation_details` on the user to return `{place:, role:}`; without it the
  place is the app name. The inviter shows by `full_name`, or their address.
- Override `can_be_invited?` on the user to refuse invites (by default, users
  who already have an address), and `after_invitation_accepted(user)` in the
  controller for analytics.

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
