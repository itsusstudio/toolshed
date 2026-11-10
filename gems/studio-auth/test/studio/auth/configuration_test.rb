require "test_helper"

class Studio::Auth::ConfigurationTest < ActiveSupport::TestCase
  Configuration = Studio::Auth::Configuration

  test "validate_config! requires every setting, including both session limits" do
    error = assert_raises(Configuration::Error) { Configuration.new.validate_config! }

    assert_match "set c.app_name, c.mail_from, c.support_email, c.mail_logo_url, c.terms_url, c.privacy_url, c.session_idle_timeout, c.session_absolute_timeout in config/initializers/studio_auth.rb", error.message
  end

  test "in production the logo must be an https URL" do
    config = valid_config
    config.mail_logo_url = "/mail/mark.png"
    Rails.env.stubs(:production?).returns(true)

    assert_match "c.mail_logo_url must be a full https URL", assert_raises(Configuration::Error) { config.validate_config! }.message
  end

  test "a session limit must be a duration" do
    config = valid_config
    config.session_absolute_timeout = 90

    assert_match "c.session_absolute_timeout", assert_raises(Configuration::Error) { config.validate_config! }.message
  end

  test "staff writes in the admin area need a sign-in within 12 hours at most" do
    config = valid_config
    config.staff_read_sign_in_max_age = 30.days
    config.staff_write_sign_in_max_age = 1.day

    assert_match "c.staff_write_sign_in_max_age can be at most 12 hours",
      assert_raises(Configuration::Error) { config.validate_config! }.message
  end

  test "app review accounts come from credentials, normalized" do
    stub_app_review_accounts({" Review@Studio.com": 381904})

    assert_equal "381904", Studio::Auth::AppReviewAccounts.code_for("review@studio.com")
    assert Studio::Auth::AppReviewAccounts.include?("REVIEW@studio.com")
  end

  test "validate_config! refuses an app review account with a missing, blank or short code" do
    [nil, "", "1234", 42424].each do |code|
      stub_app_review_accounts({"review@studio.com": code})

      error = assert_raises(Configuration::Error) { valid_config.validate_config! }
      assert_match "codes must be 6 digits, in quotes, for review@studio.com", error.message
      assert_match "bin/rails credentials:edit --environment test", error.message
    end
  end

  test "validate_config! allows at most two app review accounts" do
    stub_app_review_accounts({"apple@studio.com": "111111", "google@studio.com": "222222"})
    assert_nil valid_config.validate_config!

    stub_app_review_accounts({"apple@studio.com": "111111", "google@studio.com": "222222", "extra@studio.com": "333333"})
    error = assert_raises(Configuration::Error) { valid_config.validate_config! }
    assert_match "allows at most 2 accounts", error.message
  end

  private

  def valid_config
    Configuration.new.tap do |config|
      config.app_name = "Dummy"
      config.mail_from = "hello@dummy.app"
      config.support_email = "support@dummy.app"
      config.mail_logo_url = "https://dummy.app/mail/logo.png"
      config.terms_url = "https://dummy.app/terms"
      config.privacy_url = "https://dummy.app/privacy"
      config.session_idle_timeout = 30.days
      config.session_absolute_timeout = 90.days
    end
  end

  def stub_app_review_accounts(entries)
    Rails.application.credentials.stubs(:dig).with(:studio_auth, :app_review_accounts).returns(entries)
  end
end
