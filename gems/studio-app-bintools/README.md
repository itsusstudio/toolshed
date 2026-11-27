# studio-app-bintools

Dev, database, credentials, lint and deploy scripts for studio Rails apps, run as `bin/studio <script>`.

```sh
bin/studio                         # list scripts
bin/studio help credentials-edit  # usage, also <script> --help
bin/studio db-reset
bin/studio credentials-edit staging
```

| Script | Does |
| --- | --- |
| `dev-credentials` | writes the development and test master keys from 1Password |
| `credentials-edit <env>` | edits an environment's credentials with its key from 1Password |
| `db-check [timeout]` | waits for the docker Postgres to accept connections |
| `db-reset` | rebuilds the development database from schema.rb, migrates and seeds |
| `release` | prepares the database and dumps the schema cache; call it from docker-entrypoint |
| `ci-setup` | rebuilds the test database and installs the test browser, for bin/ci |
| `install-test-browser` | installs the Chrome for Testing version in `.chrome-for-testing-version` |
| `lint` / `style` | checks / fixes standardrb, herb, i18n-tasks and biome |
| `precommit-check [files]` | lints only staged files, for the lefthook pre-commit hook |
| `outdated` | reports outdated gems and importmap pins |
| `update` | updates gems and importmap pins |
| `staging` | rebases the current branch on main and force-pushes it to staging |
| `worktree-setup [name]` | gives a git worktree its own databases, cloned from the main checkout's, and copies the credential keys |
| `worktree-cleanup` | deletes every worktree's databases, keeping the main checkout's; asks first |

bin/dev-check is not a studio script: it is copied into the app, which owns it, because bin/setup runs it before `bundle install`.

## Setup

Add `gem "studio-app-bintools"` to the toolshed block in the Gemfile, then:

```sh
bin/rails generate studio:app_bintools:install
```

This adds bin/studio and bin/dev-check, and pins the test browser. New scripts arrive with `bundle update studio-app-bintools`.

## Conventions

The app name is the module in config/application.rb, underscored (`Workbench` is `workbench`).

- 1Password: master keys at `op://itsusstudio/rails-master-keys-<app>/<environment>`. `RAILS_KEYS_OP_REF` overrides.
- Postgres: docker compose service `db`, user `postgres` (`POSTGRES_USER` overrides), development databases named `<app>_development*`.
- Flipper: when the app bundles flipper, db-reset and release also run `bin/rails flipper:sync`, which the app defines.
- Tools: standardrb and i18n-tasks from the bundle; herb-lint, herb-format and biome from mise.

## Git worktrees

Each worktree gets its own development and test databases, so one branch's migrations, jobs and test runs never touch another's. A worktree is named in `/.worktree` at the repo root (git-ignored); the app adds that name to its database names. Two changes in the app:

```ruby
# config/boot.rb, after the BUNDLE_GEMFILE line
worktree_file = File.expand_path("../../.worktree", __dir__)
ENV["WORKTREE"] ||= File.read(worktree_file).strip if File.exist?(worktree_file)
```

```yaml
# config/database.yml: first line, then <%= worktree %> after <app>_test and <app>_development in every name
<% worktree = "_#{ENV["WORKTREE"]}" if ENV["WORKTREE"].present? %>
  database: myapp_development<%= worktree %>_queue
```

`boot.rb` reads `../../.worktree` for a monorepo app in `server/`; use `../.worktree` when the app is the repo root. The main checkout has no `.worktree`, so its names don't change. Production names never use it.

In a new worktree, a person runs `bin/studio worktree-setup` (it copies credential keys, so not an agent), then restarts the dev server. `bin/studio worktree-cleanup` removes every worktree's databases.

## Adding a script

Put it in `libexec/`, executable, with a `# Summary:` line under the shebang, and a `# Usage:` line under that if it takes arguments. bin/studio answers `--help` itself, so the script never sees it. It runs from the app root, with `STUDIO_APP` and `STUDIO_FLIPPER` set.
