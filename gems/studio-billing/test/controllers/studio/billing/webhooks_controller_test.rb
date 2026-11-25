require "test_helper"

class Studio::Billing::WebhooksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Studio::Billing.reset!
    StudioBillingFixtures.configure!
  end

  test "POST with a bad signature answers 400 and enqueues nothing" do
    post "/billing/webhooks", params: event_payload("customer.subscription.updated"),
      headers: {"Stripe-Signature" => "t=1,v1=nope", "Content-Type" => "application/json"}

    assert_response :bad_request
    assert_no_enqueued_jobs
  end

  test "POST with a handled event answers 200 and enqueues the job" do
    payload = event_payload("customer.subscription.updated")

    expected_args = [{event_id: "evt_1", event_type: "customer.subscription.updated"}]
    assert_enqueued_with(job: Studio::Billing::ProcessStripeWebhookJob, args: expected_args) do
      post "/billing/webhooks", params: payload, headers: signed_headers(payload)
    end
    assert_response :ok
  end

  test "POST with an event the gem doesn't handle answers 200 and enqueues nothing" do
    payload = event_payload("customer.created")

    post "/billing/webhooks", params: payload, headers: signed_headers(payload)

    assert_response :ok
    assert_no_enqueued_jobs
  end

  private

  def event_payload(type)
    {id: "evt_1", object: "event", type: type, data: {object: {id: "sub_1", object: "subscription"}}}.to_json
  end

  def signed_headers(payload)
    timestamp = Time.current
    signature = Stripe::Webhook::Signature.compute_signature(timestamp, payload, StudioBillingFixtures::WEBHOOK_SECRET)
    {"Stripe-Signature" => "t=#{timestamp.to_i},v1=#{signature}", "Content-Type" => "application/json"}
  end
end
