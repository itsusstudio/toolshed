require "test_helper"

class Studio::Monitoring::ErrorsTest < ActiveSupport::TestCase
  test ".report sends the error to Rails.error as handled with the actor and tenant" do
    TestContext.user_id = 42
    TestContext.shop_id = 7
    error = StandardError.new("boom")

    Rails.error.expects(:report).with(error, has_entries(handled: true, context: has_entries(actor_id: 42, tenant_id: 7)))

    Studio::Monitoring::Errors.report(error)
  end

  test ".report merges caller context over the defaults" do
    error = StandardError.new("boom")

    Rails.error.expects(:report).with(error, has_entries(context: has_entry(url: "https://example.com")))

    Studio::Monitoring::Errors.report(error, context: {url: "https://example.com"})
  end
end
