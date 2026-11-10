# studio-tenancy

The studio tenant model for Rails apps on studio-auth. An organization pays
and is administered; workspaces inside it hold the data and are shared with
the people invited into them.

```
Organization          billing, owned through organization memberships
  └─ Workspace        the app's data; shared through workspace memberships
```

## Rules

- At signup every user gets an organization they own, and a first workspace in
  it, both named after them. Apps word them on screen through i18n ("Emma's
  space").
- `OrganizationMembership` joins a user to an organization, `WorkspaceMembership` to a
  workspace. Both take a `role`: `owner`, `admin`, `member` or `guest`, one per
  user and organization or workspace. Apps decide what each role may do, in
  their policies.
- Someone invited into a workspace joins the workspace only, not its
  organization: they work under the host's organization and its plan.
- A user has at most one default workspace (`is_default`), the one they're in.
  Without one, the oldest workspace they own.
- Destroying a user destroys the organizations they own, with their workspaces
  and data, and leaves the workspaces they only joined.

## Install

```ruby
git "https://github.com/itsusstudio/toolshed", branch: "main", glob: "gems/*/*.gemspec" do
  gem "studio-auth"
  gem "studio-tenancy"
end
```

```sh
bin/rails generate studio:tenancy:install
bin/rails db:migrate
```

The users table needs a `name`. The generator writes the migration and the four
models, which are the app's to extend with its own associations and columns.

```ruby
class User < ApplicationRecord
  include Studio::Auth::ForUser
  include Studio::Tenancy::ForUser
end

class Organization < ApplicationRecord
  include Studio::Tenancy::ForOrganization
end

class OrganizationMembership < ApplicationRecord
  include Studio::Tenancy::ForOrganizationMembership
end

class Workspace < ApplicationRecord
  include Studio::Tenancy::ForWorkspace
end

class WorkspaceMembership < ApplicationRecord
  include Studio::Tenancy::ForWorkspaceMembership
end

class ApplicationController < ActionController::Base
  include Studio::Auth::ForController
  include Studio::Tenancy::ForController
end
```

## Use

In controllers and views, nil when signed out:

- `current_workspace`: the user's default workspace. Scope the app's data to it.
- `current_organization`: the workspace's organization, the one that pays. Check
  plans and entitlements here; `current_organization.owner` is who pays.

Tenant data belongs to a workspace: `has_many :recipes, dependent: :destroy` on
`Workspace`, a `workspace_id` on the table. Billing belongs to the organization.
