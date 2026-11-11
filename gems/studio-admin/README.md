# studio-admin

The studio admin area for Rails apps on studio-auth: the app's admin pages,
Mission Control Jobs, Flipper UI and PgHero, all under `/admin` and open to
staff only.

## Install

```ruby
git "https://github.com/itsusstudio/toolshed", branch: "main", glob: "gems/*/*.gemspec" do
  gem "studio-auth"
  gem "studio-admin"
end
```

The gem brings `mission_control-jobs`, `flipper-ui` and `pghero`, so the app
doesn't list them.

```ruby
# app/controllers/admin_base_controller.rb
class AdminBaseController < ApplicationController
  include Studio::Admin::ForAdminController
end
```

```ruby
# config/initializers/studio_admin.rb
Studio::Admin.configure do |c|
  # How recently staff must have signed in to view the admin area, and to
  # change anything in it. Writes allow 12.hours at most.
  c.read_sign_in_max_age = 12.hours
  c.write_sign_in_max_age = 12.hours
end
```

```ruby
# config/routes.rb, last
studio_admin do
  root "dashboard#show"
  resources :users, only: [:index, :show]
end
```

## Use

- The block is `namespace :admin`: paths under `/admin`, controllers in
  `Admin::`, helpers like `admin_users_path` and `admin_root_path`.
- The tools sit at `/admin/jobs`, `/admin/flipper` and `/admin/pghero`
  (`admin_jobs_path`, `admin_flipper_path`, `admin_pghero_path`). Mission
  Control runs on `AdminBaseController`, without its HTTP basic auth.
- Every other `/admin` path, and a tool whose staff check fails, goes through
  `AdminBaseController` to the staff checks: sign in, sign in again, or a
  404.
- Call `studio_admin` last in `routes.rb`. Its catch-all answers every `/admin`
  path, so an admin route drawn after it never matches.

- Everyone but staff gets a 404. Signed-out visitors are sent to sign in
  first.
- Staff sign in again once their session is older than
  `read_sign_in_max_age` to view, or `write_sign_in_max_age` to change
  anything, and come back to the page.
- Every change through the app's admin pages and Mission Control emits
  `admin.action`, the audit trail; refused visits emit `admin.access_denied`.

Who counts as staff is studio-auth's `users.staff`.
