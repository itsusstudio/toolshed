require "test_helper"

class Studio::SettingsTest < ActiveSupport::TestCase
  test ".build turns nested hashes into dot-accessible Data objects" do
    settings = Studio::Settings.build({product: {name: "Belly"}})

    assert_kind_of Data, settings.product
    assert_equal "Belly", settings.product.name
  end

  test ".build raises on an unknown key rather than returning nil" do
    settings = Studio::Settings.build({product: {name: "Belly"}})

    assert_raises(NoMethodError) { settings.product.naem }
  end

  test ".build leaves other values untouched" do
    assert_equal ["/r/*"], Studio::Settings.build(["/r/*"])
    assert_nil Studio::Settings.build(nil)
  end

  test "config_for merges shared into the current environment" do
    settings = Rails.application.config.x.app

    assert_equal "Belly", settings.product.name
    assert_equal "belly.localhost", settings.application.app_host
  end

  test ".for_env loads another environment's settings" do
    assert_equal "my.usebelly.app", Studio::Settings.for_env("production").application.app_host
  end
end
