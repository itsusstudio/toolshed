require "test_helper"

class Studio::AppBintools::ScriptsTest < ActiveSupport::TestCase
  include ScriptHelper

  test "dev-credentials writes the development and test keys from the app's 1Password item" do
    fake "op", 'echo "key-for-${2##*/}"'

    _, status = run_script("dev-credentials")

    assert status.success?
    assert_includes calls, "op read op://itsusstudio/rails-master-keys-belly/development"
    assert_includes calls, "op read op://itsusstudio/rails-master-keys-belly/test"
    assert_equal "key-for-development\n", File.read(File.join(@app, "config/credentials/development.key"))
    assert_equal "key-for-test\n", File.read(File.join(@app, "config/credentials/test.key"))
  end

  test "dev-credentials makes the keys readable by their owner only, even ones already there" do
    fake "op", 'echo "key"'
    key = File.join(@app, "config/credentials/development.key")
    FileUtils.mkdir_p(File.dirname(key))
    File.write(key, "old\n")
    File.chmod(0o644, key)

    run_script("dev-credentials")

    assert_equal 0o600, File.stat(key).mode & 0o777
    assert_equal 0o600, File.stat(File.join(@app, "config/credentials/test.key")).mode & 0o777
  end

  test "dev-credentials honors RAILS_KEYS_OP_REF" do
    fake "op", 'echo "key"'

    run_script("dev-credentials", env: {"RAILS_KEYS_OP_REF" => "op://other/item"})

    assert_includes calls, "op read op://other/item/development"
  end

  test "dev-credentials fails when a key cannot be read" do
    fake "op", "exit 1"

    _, status = run_script("dev-credentials")

    refute status.success?
  end

  test "credentials-edit opens the environment's credentials with its key from 1Password" do
    fake "op"

    _, status = run_script("credentials-edit", "staging")

    assert status.success?
    assert_equal ["op run -- bin/rails credentials:edit --environment staging"], calls
  end

  test "credentials-edit rejects unknown environments" do
    output, status = run_script("credentials-edit", "prod")

    refute status.success?
    assert_match "unknown environment 'prod'", output
  end

  test "db-check waits on postgres as the postgres user" do
    fake "docker"

    _, status = run_script("db-check")

    assert status.success?
    assert_equal ["docker compose exec -T db pg_isready -U postgres"], calls
  end

  test "db-check gives up after the timeout" do
    fake "docker", "exit 1"

    output, status = run_script("db-check", "1")

    refute status.success?
    assert_match "did not become ready within 1s", output
  end

  test "db-reset drops connections to every development database, rebuilds and seeds" do
    fake "git"
    fake "docker"
    fake "bin/rails"

    _, status = run_script("db-reset")

    assert status.success?
    assert_equal "git checkout db/schema.rb", calls[0]
    assert_match(/-U postgres .*datname LIKE 'belly_development%'/, calls[1])
    assert_equal [
      "bin/rails db:drop:primary db:create:primary db:schema:load:primary",
      "bin/rails db:migrate:primary",
      "bin/rails db:seed"
    ], calls[2..]
  end

  test "db-reset syncs feature flags in flipper apps" do
    fake "git"
    fake "docker"
    fake "bin/rails"

    run_script("db-reset", env: {"STUDIO_FLIPPER" => "1"})

    assert_equal "bin/rails flipper:sync", calls.last
  end

  test "db-reset refuses to run outside development" do
    fake "git"

    output, status = run_script("db-reset", env: {"RAILS_ENV" => "production"})

    refute status.success?
    assert_match "only runs against development", output
    assert_empty calls
  end

  test "release prepares the database and dumps the schema cache" do
    fake "bin/rails"

    run_script("release")

    assert_equal ["bin/rails db:prepare", "bin/rails db:schema:cache:dump"], calls
  end

  test "release syncs feature flags in flipper apps" do
    fake "bin/rails"

    run_script("release", env: {"STUDIO_FLIPPER" => "1"})

    assert_equal "bin/rails flipper:sync", calls.last
  end

  test "precommit-check lints only the given files, by type" do
    fake "mise"

    _, status = run_script("precommit-check", "app/models/recipe.rb", "app/views/recipes/show.html.erb")

    assert status.success?
    assert_equal [
      "mise exec -- bundle exec standardrb app/models/recipe.rb",
      "mise exec -- herb-lint --simple app/views/recipes/show.html.erb",
      "mise exec -- herb-format --check app/views/recipes/show.html.erb"
    ], calls
  end

  test "precommit-check runs i18n-tasks when locales change and fails when a check fails" do
    fake "mise", "exit 1"

    _, status = run_script("precommit-check", "config/locales/en.yml")

    refute status.success?
    assert_equal ["mise exec -- bundle exec i18n-tasks health"], calls
  end

  test "outdated treats exit 1 as a finding but stops on other failures" do
    fake "bundle", "exit 1"
    fake "bin/importmap", "exit 2"

    _, status = run_script("outdated")

    assert_equal 2, status.exitstatus
    assert_equal ["bundle outdated --only-explicit", "bin/importmap outdated"], calls
  end

  test "update updates gems then importmap pins" do
    fake "bundle"
    fake "bin/importmap"

    _, status = run_script("update")

    assert status.success?
    assert_equal ["bundle update", "bin/importmap update"], calls
  end

  test "update stops when a step fails" do
    fake "bundle", "exit 1"
    fake "bin/importmap"

    _, status = run_script("update")

    refute status.success?
    assert_equal ["bundle update"], calls
  end

  test "staging refuses to deploy the staging branch itself" do
    fake "git", 'echo "staging"'

    output, status = run_script("staging")

    refute status.success?
    assert_match "not 'staging' itself", output
  end

  test "staging rebases the current branch on main and force-pushes it to staging" do
    fake "git", '[ "$1" = "rev-parse" ] && echo "feature"; true'

    _, status = run_script("staging")

    assert status.success?
    assert_equal [
      "git rev-parse --abbrev-ref HEAD",
      "git fetch origin",
      "git rebase origin/main",
      "git push --force origin HEAD:staging"
    ], calls
  end

  test "install-test-browser is a no-op once the pinned version is installed" do
    File.write(File.join(@app, ".chrome-for-testing-version"), "131.0.1\n")
    FileUtils.mkdir_p(File.join(@app, ".chrome-for-testing"))
    File.write(File.join(@app, ".chrome-for-testing/installed-version"), "131.0.1")
    File.write(File.join(@app, ".chrome-for-testing/executable-path"), File.join(@fakes, "chrome"))
    fake "chrome"
    fake "npx"

    output, status = run_script("install-test-browser")

    assert status.success?
    assert_match "already installed", output
    assert_empty calls
  end
end
