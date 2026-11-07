require "test_helper"

class Studio::Monitoring::ErrorsTest < ActiveSupport::TestCase
  test ".report reports to Rails.error as handled with the caller's context" do
    error = StandardError.new("boom")

    Rails.error.expects(:report).with(error, context: {url: "https://example.com"})

    Studio::Monitoring::Errors.report(error, context: {url: "https://example.com"})
  end

  test ".report passes Rails.error options through" do
    error = StandardError.new("boom")

    Rails.error.expects(:report).with(error, context: {}, severity: :error, source: "importer")

    Studio::Monitoring::Errors.report(error, severity: :error, source: "importer")
  end

  test ".handle swallows and reports the error" do
    Rails.error.expects(:report).with(instance_of(RuntimeError), has_entries(handled: true))

    assert_nil Studio::Monitoring::Errors.handle { raise "boom" }
  end

  test ".record reports and re-raises" do
    Rails.error.expects(:report).with(instance_of(RuntimeError), has_entries(handled: false))

    assert_raises(RuntimeError) { Studio::Monitoring::Errors.record { raise "boom" } }
  end
end
