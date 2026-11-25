require "test_helper"

class Studio::Billing::MaintenanceJobsTest < StudioBillingTestCase
  NOW = Time.zone.local(2026, 11, 25, 12)

  test "PurgeWebhookEventsJob deletes events older than the retention and keeps the rest" do
    travel_to NOW do
      Studio::Billing::WebhookEvent.create!(stripe_event_id: "evt_old", event_type: "invoice.paid",
        created_at: 91.days.ago)
      Studio::Billing::WebhookEvent.create!(stripe_event_id: "evt_new", event_type: "invoice.paid",
        created_at: 89.days.ago)

      Studio::Billing::PurgeWebhookEventsJob.perform_now

      assert_equal ["evt_new"], Studio::Billing::WebhookEvent.pluck(:stripe_event_id)
    end
  end

  test "CheckStripeJob reports drift as a warning with each difference" do
    change = Studio::Billing::Sync::Change.new(action: :replace, subject: "price team_yearly", detail: "x",
      perform: -> {})
    Studio::Billing::Sync.stubs(:new).returns(stub(in_sync?: false, changes: [change]))
    Rails.error.expects(:report).with(
      instance_of(Studio::Billing::CheckStripeJob::DriftError),
      has_entries(severity: :warning, context: {differences: [change.to_s]})
    )

    Studio::Billing::CheckStripeJob.perform_now
  end

  test "CheckStripeJob reports nothing when Stripe matches" do
    Studio::Billing::Sync.stubs(:new).returns(stub(in_sync?: true))
    Rails.error.expects(:report).never

    Studio::Billing::CheckStripeJob.perform_now
  end
end
