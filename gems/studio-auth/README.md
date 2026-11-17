# studio-auth

Passwordless sign-in and sign-up for studio Rails apps: a 6-digit email code,
expiring database sessions, the staff flag, and lockout mail.

## Rules

| | |
| --- | --- |
| Code | 6 digits, valid 10 minutes, single use, 5 attempts. Asking again from the same browser within 60 seconds returns the same code, except "Send a new code", which mails a fresh one and ends the old one, at most once every 30 seconds |
| Lockout | 10 wrong codes in 24 hours pause sign-in for 1 hour, plus 1 hour per further wrong code. A known device counts only its own wrong codes |
| Limits | 5 code requests an hour per address (a known device has its own 5), 30 an hour per IP (per /64 for IPv6), also counted in the database |
| Unknown address | No mail. With sign-up, a page says there's no account for that address and offers "Create an account" or "Use a different email address"; without, an error under the field. Sign-up codes come only from the app's signup form (`start_sign_up_for`) |
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
  c.mail_address = ["it's us studio", "216-4035 rue Saint-Ambroise", "Montréal QC H4C 2E1"]
  c.page_layout = "uniform" # the app's Uniform document layout
  c.wordmark = "sans" # the app name's voice: "serif" or "sans"
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

## Upgrading

Login codes are keyed by email address. An app installed before that adds the
column and drops `user_id` once the new code is deployed:

```ruby
add_column :studio_auth_login_codes, :email_address, :string
add_index :studio_auth_login_codes, [:email_address, :created_at], algorithm: :concurrently
```

Invitations need the `studio_auth_invitations` table; copy its `create_table`
from the install template into a migration.

## Sign-in pages and mail

The gem owns the sign-in and code pages and the sign-in mail: markup, copy
(en, fr, nl) and the server logic behind them. They're built from
[Uniform](https://github.com/itsusstudio/uniform) and nothing else: the pages
sit in `u-auth-shell`, the code field is `<u-input-code submit>`, and the mail
uses Uniform's layout and blocks. The gem ships no CSS, JavaScript or logo.
Every studio app shows the same pages and mail. The app supplies only:

- its name, set as a Uniform wordmark in the voice `c.wordmark` names
- a blurb under the name, as `studio_auth.blurb` in its own locale files
  (optional)
- `c.mail_address`, the sender's name, street and city at the foot of each mail
- a Uniform document layout, named by `c.page_layout`, that links Uniform's
  stylesheets and renders the gem's page block in its body:
  `<%= content_for?(:studio_auth_page) ? yield(:studio_auth_page) : yield %>`
  (the gem also sets `content_for :page_title`)

The sign-in page shows "Don't have an account? Create one" under the email
field, linked to the app's `signup` route when it has one.

App pages can use the same frame with `layout "studio/auth"`.

Don't copy the gem's views into the app: a view at the same path overrides
the gem's and the pages drift apart again. Reword through the app's own
locale files (`studio_auth.codes.new.title`, ...) only where a locale needs it.

## Use

- `allow_unauthenticated_access only: [...]` opens actions to signed-out visitors.
- `authenticated?` and `current_user` in controllers and views.
- Sign-up: an app that routes `signup_path` takes sign-ups. Its signup form
  keeps what it collected (in the session, say) and calls
  `start_sign_up_for(email_address)`, which creates nothing. When the code is
  right the gem calls the app's `create_account_for(email_address)`, which
  returns the new user, nil to send the visitor back to sign in, or redirects.
  An address that already has an account just signs in.
- By default `create_account_for` remembers, for 30 minutes, that this browser
  proved the address, and redirects to `signup_path`. The address stays in the
  session, never the URL. The signup form fills its email field from
  `verified_email_address`, and when `verified_email_address?(email_address)`
  holds on submit it creates the user and calls `start_new_session_for(user)`
  instead of mailing a second code.
- `new_account_email_address` is the address typed on the sign-in page in the
  last 30 minutes that had no account. It is unverified: a signup form only
  prefills its email field from it.
- `start_sign_in_for(user)` mails a code to an existing user.
- `store_return_path(path)` returns a visitor to `path` after sign-in.
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
