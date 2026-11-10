require "test_helper"

class Studio::Auth::ConfigurationTest < ActiveSupport::TestCase
  Configuration = Studio::Auth::Configuration

  test "validate! requires app_name, mail_from and support_email" do
    error = assert_raises(Configuration::Error) { Configuration.new.validate! }

    assert_match "set c.app_name, c.mail_from, c.support_email in config/initializers/studio_auth.rb", error.message
  end

  test "review accounts come from credentials, normalized" do
    stub_review_accounts([{email_address: " Review@Studio.com", login_code: 381904}])

    assert_equal "381904", Studio::Auth::ReviewAccounts.code_for("review@studio.com")
    assert Studio::Auth::ReviewAccounts.include?("REVIEW@studio.com")
  end

  test "validate! refuses a review account with a missing, blank or short code" do
    [{email_address: "review@studio.com"}, {email_address: "review@studio.com", login_code: ""}, {email_address: "review@studio.com", login_code: "1234"}].each do |entry|
      stub_review_accounts([entry])

      error = assert_raises(Configuration::Error) { valid_config.validate! }
      assert_match "login_code must be 6 digits for review@studio.com", error.message
      assert_match "bin/rails credentials:edit --environment test", error.message
    end
  end

  test "validate! refuses a review account without an email address" do
    stub_review_accounts([{login_code: "381904"}])

    error = assert_raises(Configuration::Error) { valid_config.validate! }
    assert_match "has an entry with no email_address", error.message
  end

  test "validate! allows at most two review accounts" do
    stub_review_accounts([
      {email_address: "apple@studio.com", login_code: "111111"},
      {email_address: "google@studio.com", login_code: "222222"}
    ])
    assert_nil valid_config.validate!

    stub_review_accounts([
      {email_address: "apple@studio.com", login_code: "111111"},
      {email_address: "google@studio.com", login_code: "222222"},
      {email_address: "extra@studio.com", login_code: "333333"}
    ])
    error = assert_raises(Configuration::Error) { valid_config.validate! }
    assert_match "allows at most 2 accounts", error.message
  end

  test "undeliverable catches reserved and placeholder domains" do
    deliverability = Studio::Auth::Deliverability

    assert deliverability.undeliverable?("a@example.com")
    assert deliverability.undeliverable?("a@shop.test")
    assert deliverability.undeliverable?("a@test.com")
    assert deliverability.undeliverable?("nope")
    refute deliverability.undeliverable?("a@usebelly.app")
  end

  private

  def valid_config
    Configuration.new.tap do |config|
      config.app_name = "Dummy"
      config.mail_from = "hello@dummy.app"
      config.support_email = "support@dummy.app"
    end
  end

  def stub_review_accounts(entries)
    Rails.application.credentials.stubs(:dig).with(:studio_auth, :review_accounts).returns(entries)
    Studio::Auth::ReviewAccounts.reset!
  end
end
