require "test_helper"

class Studio::AppBintools::InstallGeneratorTest < Rails::Generators::TestCase
  tests Studio::AppBintools::InstallGenerator
  destination File.expand_path("../../../tmp/generator", __dir__)
  setup :prepare_destination
  setup { Studio::AppBintools::InstallGenerator.any_instance.stubs(:run) }

  test "adds the bin/studio binstub and copies dev-check" do
    Studio::AppBintools::InstallGenerator.any_instance.expects(:run).with("bundle binstubs studio-app-bintools")

    run_generator

    assert_file "bin/dev-check", /docker compose version/
    assert File.executable?(File.join(destination_root, "bin/dev-check"))
  end

  test "pins the test browser and ignores its install dir once" do
    File.write(File.join(destination_root, ".gitignore"), "/tmp/\n")

    run_generator
    run_generator ["--force"]

    assert_file ".chrome-for-testing-version", "stable\n"
    assert_equal 1, File.read(File.join(destination_root, ".gitignore")).scan("/.chrome-for-testing/").size
  end

  test "keeps an app's pinned browser version" do
    File.write(File.join(destination_root, ".chrome-for-testing-version"), "131.0.1\n")

    run_generator ["--force"]

    assert_file ".chrome-for-testing-version", "131.0.1\n"
  end
end
