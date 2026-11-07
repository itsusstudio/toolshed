# studio-app-bintools

Dev, database, credentials, lint and deploy scripts for studio Rails apps, run as `bin/studio <script>`.

```sh
bin/studio                         # list scripts
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

## Adding a script

Put it in `libexec/`, executable, with a `# Summary:` line under the shebang. It runs from the app root, with `STUDIO_APP` and `STUDIO_FLIPPER` set.
