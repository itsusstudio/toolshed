require "test_helper"

class Studio::FlagsTest < ActiveSupport::TestCase
  setup { Flipper.instance = nil }

  test ".names lists the registry's flags in file order" do
    assert_equal ["feature_enable_bella", "killswitch_bookmark_details_cache", "feature_enable_bare"], Studio::Flags.names
  end

  test ".descriptions maps each flag to its description, blank when it has none" do
    assert_equal "On: Bella answers. Off: hidden.", Studio::Flags.descriptions["feature_enable_bella"]
    assert_equal "", Studio::Flags.descriptions["feature_enable_bare"]
  end

  test ".sync! adds registered flags, off, and removes unregistered ones" do
    Flipper.enable("feature_enable_retired")

    sync = Studio::Flags.sync!

    assert_equal Studio::Flags.names, sync.added
    assert_equal ["feature_enable_retired"], sync.removed
    assert_equal Studio::Flags.names.sort, Flipper.features.map(&:key).sort
    assert Studio::Flags.names.none? { Flipper.enabled?(it) }
  end

  test ".sync! keeps the state of flags Flipper already has" do
    Flipper.enable("feature_enable_bella")

    sync = Studio::Flags.sync!

    refute_includes sync.added, "feature_enable_bella"
    assert Flipper.enabled?("feature_enable_bella")
  end

  test "a missing registry means no flags" do
    Rails.stubs(:root).returns(Pathname(Dir.tmpdir))

    assert_empty Studio::Flags.names
  end

  test "the Flipper UI shows descriptions and can't create or remove flags" do
    ui = Flipper::UI.configuration

    refute ui.feature_creation_enabled
    refute ui.feature_removal_enabled
    assert_equal Studio::Flags.descriptions, ui.descriptions_source.call([])
    assert_equal "Test", ui.banner_text
  end

  test "flipper:sync prints what changed" do
    Flipper.enable("feature_enable_retired")

    output = capture_io { Rake::Task["flipper:sync"].execute }.first

    assert_includes output, "  + feature_enable_bella"
    assert_includes output, "  - feature_enable_retired"
  end
end

class Studio::Flags::TestHelperTest < ActiveSupport::TestCase
  include Studio::Flags::TestHelper

  test "every registered flag exists before the test runs" do
    assert Studio::Flags.names.all? { Flipper.exist?(it) }
  end
end
