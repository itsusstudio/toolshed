require "test_helper"

class Studio::AppBintoolsTest < ActiveSupport::TestCase
  setup { @root = Dir.mktmpdir }
  teardown { FileUtils.remove_entry(@root) }

  test "app name is the underscored top-level module of config/application.rb" do
    write_application "module DejaYum\n  class Application < Rails::Application\n  end\nend\n"

    assert_equal "deja_yum", Studio::AppBintools.app_name(@root)
  end

  test "app name raises when config/application.rb has no module" do
    write_application "class Application < Rails::Application\nend\n"

    assert_raises(Studio::AppBintools::Error) { Studio::AppBintools.app_name(@root) }
  end

  test "env flags flipper only when the app bundles it" do
    write_application "module Belly\nend\n"

    Gem.stubs(:loaded_specs).returns({})
    assert_equal({"STUDIO_APP" => "belly", "STUDIO_FLIPPER" => nil}, Studio::AppBintools.env(@root))

    Gem.stubs(:loaded_specs).returns({"flipper" => Object.new})
    assert_equal "1", Studio::AppBintools.env(@root)["STUDIO_FLIPPER"]
  end

  test "cli replaces the process with the named script, run from the app root" do
    write_application "module Belly\nend\n"
    script = File.join(Studio::AppBintools::LIBEXEC, "db-check")

    Kernel.expects(:exec).with(Studio::AppBintools.env(@root), script, "5", chdir: @root)

    Studio::AppBintools.cli ["db-check", "5"], root: @root
  end

  test "cli with no script lists every script with its summary" do
    out = StringIO.new

    Studio::AppBintools.cli [], root: @root, out: out

    assert_match "Usage: bin/studio <script> [args]", out.string
    assert_match(/^  db-reset +Rebuild the development database from schema.rb, migrate and seed$/, out.string)
    assert_equal Studio::AppBintools::SCRIPTS.size, out.string.scan(/^  \S/).size
  end

  test "cli rejects unknown scripts with the list and a failing exit" do
    Kernel.expects(:exec).never

    _, err = capture_io do
      assert_equal 1, Studio::AppBintools.cli(["rake"], root: @root)
    end

    assert_match "unknown script: rake", err
    assert_match "db-reset", err
  end

  test "help flags after a script print its usage and never run it" do
    Kernel.expects(:exec).never

    ["--help", "-h"].each do |flag|
      out = StringIO.new
      assert_equal 0, Studio::AppBintools.cli(["db-reset", flag], root: @root, out: out)
      assert_equal "Usage: bin/studio db-reset\n\nRebuild the development database from schema.rb, migrate and seed\n", out.string
    end
  end

  test "help <script> prints its usage line" do
    out = StringIO.new

    assert_equal 0, Studio::AppBintools.cli(["help", "credentials-edit"], root: @root, out: out)
    assert_match "Usage: bin/studio credentials-edit <development|test|staging|production>", out.string
  end

  test "help with no script lists every script" do
    out = StringIO.new

    Studio::AppBintools.cli ["help"], root: @root, out: out

    assert_equal Studio::AppBintools::SCRIPTS.size, out.string.scan(/^  \S/).size
  end

  test "every script has a summary, is executable and finds the app through its cwd" do
    Studio::AppBintools.summaries.each do |script, summary|
      path = File.join(Studio::AppBintools::LIBEXEC, script)

      assert_predicate summary, :present?
      assert File.executable?(path), "#{script} is not executable"
      refute_match(/dirname "\$0"/, File.read(path), "#{script} resolves paths from the gem, not the app")
    end
  end

  private

  def write_application(source)
    FileUtils.mkdir_p(File.join(@root, "config"))
    File.write(File.join(@root, "config/application.rb"), source)
  end
end
