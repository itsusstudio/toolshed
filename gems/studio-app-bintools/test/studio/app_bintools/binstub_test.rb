require "test_helper"

# End to end: a real app bundle, a real `bundle binstubs`, and bin/studio
# run from outside the app, so the app root must come from the binstub.
class Studio::AppBintools::BinstubTest < ActiveSupport::TestCase
  setup do
    @app = Dir.mktmpdir("app")
    gem_path = File.expand_path("../../..", __dir__)
    File.write(File.join(@app, "Gemfile"), %(source "https://rubygems.org"\ngem "studio-app-bintools", path: "#{gem_path}"\n))
    FileUtils.mkdir_p(File.join(@app, "config"))
    File.write(File.join(@app, "config/application.rb"), "module Belly\nend\n")
    File.write(File.join(@app, "bin-rails"), %(#!/usr/bin/env bash\necho "$PWD $*" >> calls.log\n))

    Bundler.with_unbundled_env do
      system("bundle install --local --quiet && bundle binstubs studio-app-bintools", chdir: @app, exception: true)
    end
    File.rename(File.join(@app, "bin-rails"), File.join(@app, "bin/rails"))
    File.chmod(0o755, File.join(@app, "bin/rails"))
  end

  teardown { FileUtils.remove_entry(@app) }

  test "bin/studio runs the gem's script from the app root" do
    output, status = Bundler.with_unbundled_env do
      Open3.capture2e(File.join(@app, "bin/studio"), "release", chdir: "/")
    end

    assert status.success?, output
    assert_equal ["#{@app} db:prepare", "#{@app} db:schema:cache:dump"], File.readlines(File.join(@app, "calls.log"), chomp: true)
  end
end
