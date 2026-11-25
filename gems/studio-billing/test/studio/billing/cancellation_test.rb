require "test_helper"

class Studio::Billing::CancellationTest < StudioBillingTestCase
  NOW = Time.zone.local(2026, 11, 25, 12)

  test "#cancel_billing! cancels every subscription now, records it and revokes grants" do
    travel_to NOW do
      subscription = subscribe(organization)
      grant = organization.billing_grants.create!(reason: "comp", plan_code: "team")
      client.v1.subscriptions.expects(:cancel).with(subscription.stripe_subscription_id)
        .returns(stripe_subscription(id: subscription.stripe_subscription_id, status: "canceled",
          customer: "cus_#{organization.id}"))

      organization.cancel_billing!

      assert_equal "canceled", subscription.reload.status
      assert_not_nil grant.reload.revoked_at
      assert_equal "free", organization.entitlements.plan.code
    end
  end

  test "#cancel_billing!(at_period_end: true) stops renewal and keeps access until the period ends" do
    travel_to NOW do
      subscription = subscribe(organization, period_end: 20.days.from_now)
      grant = organization.billing_grants.create!(reason: "comp", plan_code: "team")
      client.v1.subscriptions.expects(:update)
        .with(subscription.stripe_subscription_id, {cancel_at_period_end: true})
        .returns(stripe_subscription(id: subscription.stripe_subscription_id, status: "active",
          period_end: 20.days.from_now, cancel_at: 20.days.from_now, customer: "cus_#{organization.id}"))

      organization.cancel_billing!(at_period_end: true)

      assert_not_nil subscription.reload.cancel_at
      assert_nil grant.reload.revoked_at
      assert_equal "team", organization.entitlements.plan.code
    end
  end

  test "#cancel_billing! accepts a subscription Stripe already canceled" do
    travel_to NOW do
      subscription = subscribe(organization)
      client.v1.subscriptions.stubs(:cancel).raises(Stripe::InvalidRequestError.new("already canceled", nil))
      client.v1.subscriptions.stubs(:retrieve).with(subscription.stripe_subscription_id)
        .returns(stripe_subscription(id: subscription.stripe_subscription_id, status: "canceled",
          customer: "cus_#{organization.id}"))

      organization.cancel_billing!

      assert_equal "canceled", subscription.reload.status
    end
  end

  test "#cancel_billing! revokes a grant whose plan is no longer in billing.yml" do
    grant = organization.billing_grants.create!(reason: "comp", plan_code: "team")
    data = CATALOG.deep_dup
    data["plans"].reject! { it["code"] == "team" || it["code"] == "simple" }
    Studio::Billing.stubs(:catalog).returns(catalog(data))

    organization.cancel_billing!

    assert_not_nil grant.reload.revoked_at
  end

  test "#cancel_billing! skips subscriptions that already ended" do
    travel_to NOW do
      subscribe(organization, status: "canceled")
      client.v1.subscriptions.expects(:cancel).never

      organization.cancel_billing!
    end
  end

  test "#destroy refuses an owner Stripe will charge again and keeps its billing rows" do
    travel_to NOW do
      subscribe(organization)

      assert_raises(Studio::Billing::BillingStillActiveError) { organization.destroy }
      assert_equal 1, organization.billing_subscriptions.count
    end
  end

  test "#destroy goes ahead once the subscription is scheduled to end" do
    travel_to NOW do
      subscribe(organization).update!(cancel_at: 20.days.from_now)

      organization.destroy

      assert_predicate organization, :destroyed?
      assert_equal 0, Studio::Billing::Subscription.count
    end
  end

  test "#destroy goes ahead for an owner who never paid" do
    organization.destroy

    assert_predicate organization, :destroyed?
  end

  test "a canceled subscription whose owner is gone is skipped without a report" do
    Rails.error.expects(:report).never

    result = Studio::Billing::SubscriptionSync.new(client: client)
      .call(stripe_subscription(status: "canceled", owner: nil, customer: "cus_gone"))

    assert_nil result
  end
end
