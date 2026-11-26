require "test_helper"

class Studio::Billing::ProcessStripeWebhookJobTest < StudioBillingTestCase
  test "#perform syncs the subscription a subscription event names and records the organization" do
    client.v1.subscriptions.stubs(:retrieve).with("sub_1").returns(stripe_subscription)

    perform("evt_1", "customer.subscription.updated", {id: "sub_1", object: "subscription"})

    assert_equal "team", organization.entitlements.plan.code
    event = Studio::Billing::WebhookEvent.find_by!(stripe_event_id: "evt_1")
    assert_equal organization, event.organization
    assert_not_nil event.processed_at
  end

  test "#perform retries an event whose earlier attempt failed before finishing" do
    Studio::Billing::WebhookEvent.create!(stripe_event_id: "evt_1", event_type: "customer.subscription.updated")
    client.v1.subscriptions.expects(:retrieve).with("sub_1").returns(stripe_subscription)

    perform("evt_1", "customer.subscription.updated", {id: "sub_1", object: "subscription"})

    assert_not_nil Studio::Billing::WebhookEvent.find_by!(stripe_event_id: "evt_1").processed_at
  end

  test "#perform processes the same event once" do
    client.v1.subscriptions.expects(:retrieve).with("sub_1").once.returns(stripe_subscription)

    2.times { perform("evt_1", "customer.subscription.updated", {id: "sub_1", object: "subscription"}) }
  end

  test "#perform syncs the subscription behind an invoice" do
    client.v1.subscriptions.expects(:retrieve).with("sub_1").returns(stripe_subscription)

    perform("evt_2", "invoice.payment_failed",
      {id: "in_1", object: "invoice", parent: {subscription_details: {subscription: "sub_1"}}})
  end

  test "#perform records the customer from a completed subscription checkout" do
    client.v1.subscriptions.stubs(:retrieve).with("sub_1").returns(stripe_subscription(customer: "cus_new"))

    perform("evt_3", "checkout.session.completed", checkout_session)

    assert_equal "cus_new", organization.reload.stripe_customer_id
  end

  test "#perform ignores the customer of a checkout the gem didn't create" do
    client.v1.subscriptions.stubs(:retrieve).with("sub_1").returns(stripe_subscription(customer: "cus_1"))

    perform("evt_3", "checkout.session.completed", checkout_session(metadata: {}))

    assert_equal "cus_1", organization.reload.stripe_customer_id
  end

  test "#perform never replaces an organization's customer and reports the checkout" do
    organization.update!(stripe_customer_id: "cus_1")
    Rails.error.expects(:report)
      .with(instance_of(Studio::Billing::StripeCustomerMismatchError), has_entry(handled: true))
    stub_event("evt_3", "checkout.session.completed", checkout_session)

    Studio::Billing::ProcessStripeWebhookJob.perform_now(event_id: "evt_3", event_type: "checkout.session.completed")

    assert_equal "cus_1", organization.reload.stripe_customer_id
  end

  test "#perform publishes payment_problem for a dispute with the organization" do
    organization.update!(stripe_customer_id: "cus_1")
    client.v1.charges.stubs(:retrieve).with("ch_1").returns(stripe_object(id: "ch_1", customer: "cus_1"))
    payloads = []
    callback = ->(*, payload) { payloads << payload }

    event_name = Studio::Billing::ProcessStripeWebhookJob::PAYMENT_PROBLEM_EVENT
    ActiveSupport::Notifications.subscribed(callback, event_name) do
      perform("evt_4", "charge.dispute.created", {id: "dp_1", object: "dispute", charge: "ch_1"})
    end

    assert_equal organization, payloads.sole[:organization]
    assert_equal "charge.dispute.created", payloads.sole[:event_type]
  end

  test "#perform discards an event whose organization can't be found" do
    client.v1.subscriptions.stubs(:retrieve).returns(stripe_subscription(organization: nil, customer: "cus_unknown"))
    Rails.error.expects(:report).with(instance_of(Studio::Billing::OrganizationNotFoundError), has_entry(handled: true))

    stub_event("evt_5", "customer.subscription.updated", {id: "sub_1", object: "subscription"})

    Studio::Billing::ProcessStripeWebhookJob.perform_now(event_id: "evt_5", event_type: "customer.subscription.updated")

    assert_nil Studio::Billing::WebhookEvent.find_by!(stripe_event_id: "evt_5").processed_at
  end

  private

  def perform(event_id, event_type, object)
    stub_event(event_id, event_type, object)
    Studio::Billing::ProcessStripeWebhookJob.new.perform(event_id: event_id, event_type: event_type)
  end

  def checkout_session(metadata: nil)
    {
      id: "cs_1", object: "checkout.session", mode: "subscription", subscription: "sub_1", customer: "cus_new",
      client_reference_id: organization.id.to_s,
      metadata: metadata || {Studio::Billing::ORGANIZATION_METADATA_KEY => organization.id.to_s}
    }
  end

  def stub_event(event_id, event_type, object)
    client.v1.events.stubs(:retrieve).with(event_id)
      .returns(stripe_object(id: event_id, object: "event", type: event_type, data: {object: object}))
  end
end
