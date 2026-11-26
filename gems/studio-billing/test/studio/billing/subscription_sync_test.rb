require "test_helper"

class Studio::Billing::SubscriptionSyncTest < StudioBillingTestCase
  test "#call twice for the same subscription leaves one row with the latest state" do
    sync.call(stripe_subscription(status: "active"))
    sync.call(stripe_subscription(status: "past_due"))

    assert_equal 1, Studio::Billing::Subscription.count
    assert_equal "past_due", Studio::Billing::Subscription.sole.status
  end

  test "#call takes over a row another sync inserted first" do
    Studio::Billing::Subscription.create!(
      organization: organization, stripe_subscription_id: "sub_1", stripe_customer_id: "cus_1",
      stripe_price_id: "price_old", status: "incomplete", current_period_end: 1.day.from_now, synced_at: 1.minute.ago
    )

    subscription = sync.call(stripe_subscription(status: "active"))

    assert_equal 1, Studio::Billing::Subscription.count
    assert_equal "active", subscription.status
    assert_equal "price_team_yearly", subscription.stripe_price_id
  end

  test "#call stores the period end from the items, cancel_at, the plan and the customer" do
    travel_to Time.zone.local(2026, 11, 25, 12) do
      period_end = Time.zone.local(2027, 11, 25, 12)
      cancel_at = Time.zone.local(2027, 11, 25, 12)

      subscription = sync.call(stripe_subscription(period_end: period_end, cancel_at: cancel_at))

      assert_equal period_end, subscription.current_period_end
      assert_equal cancel_at, subscription.cancel_at
      assert_equal "team", subscription.plan_code
      assert_equal "team_yearly", subscription.lookup_key
      assert_equal "cus_1", organization.reload.stripe_customer_id
    end
  end

  test "#call records the Stripe customer even when the organization row fails the app's validations" do
    stripe = stripe_subscription(customer: "cus_9")
    Organization.any_instance.stubs(:valid?).returns(false)

    sync.call(stripe)

    assert_equal "cus_9", organization.reload.stripe_customer_id
  end

  test "#call keeps the organization's customer when the subscription names another, and reports it" do
    organization.update!(stripe_customer_id: "cus_1")
    Rails.error.expects(:report)
      .with(instance_of(Studio::Billing::StripeCustomerMismatchError), has_entry(handled: true))

    sync.call(stripe_subscription(customer: "cus_other"))

    assert_equal "cus_1", organization.reload.stripe_customer_id
    assert_equal 1, organization.billing_subscriptions.count
  end

  test "#call without a findable organization raises and writes nothing" do
    assert_raises(Studio::Billing::OrganizationNotFoundError) do
      sync.call(stripe_subscription(organization: nil, customer: "cus_unknown"))
    end
    assert_equal 0, Studio::Billing::Subscription.count
  end

  test "#call finds the organization through a customer it has seen before" do
    organization.update!(stripe_customer_id: "cus_known")

    subscription = sync.call(stripe_subscription(organization: nil, customer: "cus_known"))

    assert_equal organization, subscription.organization
  end

  test "#call falls back to the app's organization_from_metadata" do
    Studio::Billing.config.organization_from_metadata = ->(metadata) {
      Organization.find_by(id: metadata["repair_shop_id"])
    }
    stripe = stripe_subscription(organization: nil)
    stripe.metadata = {"repair_shop_id" => organization.id.to_s}

    assert_equal organization, sync.call(stripe).organization
  end

  test "#call stores an unknown price without a plan and reports it" do
    Rails.error.expects(:report).with(instance_of(Studio::Billing::UnknownPriceError), has_entry(handled: true))

    subscription = sync.call(stripe_subscription(lookup_key: "mystery"))

    assert_nil subscription.plan_code
  end

  test "#call publishes subscription_changed with the plans before and after" do
    payloads = []
    callback = ->(*, payload) { payloads << payload }

    ActiveSupport::Notifications.subscribed(callback, Studio::Billing::SubscriptionSync::CHANGED_EVENT) do
      sync.call(stripe_subscription)
    end

    assert_equal "free", payloads.sole[:plan_before]
    assert_equal "team", payloads.sole[:plan_after]
    assert_equal organization, payloads.sole[:organization]
  end

  test ".call re-fetches the subscription from Stripe" do
    client.v1.subscriptions.expects(:retrieve).with("sub_1").returns(stripe_subscription)

    Studio::Billing::SubscriptionSync.call("sub_1", client: client)

    assert_equal 1, Studio::Billing::Subscription.count
  end

  private

  def sync
    Studio::Billing::SubscriptionSync.new(client: client)
  end
end
