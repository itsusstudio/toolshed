require "test_helper"

class Studio::Billing::ReconcilerTest < StudioBillingTestCase
  NOW = Time.zone.local(2026, 11, 25, 12)

  test "#reconcile_changes reads only events newer than the cursor and syncs each subscription once" do
    travel_to NOW do
      Studio::Billing::SyncCursor.create!(name: "subscription_events", last_event_id: "evt_old", checked_at: 1.hour.ago)
      client.v1.events.expects(:list).with { it[:ending_before] == "evt_old" }.returns(stripe_list(
        event("evt_2", "sub_1", 2), event("evt_3", "sub_1", 3)
      ))
      client.v1.subscriptions.expects(:retrieve).with("sub_1").once.returns(stripe_subscription)

      reconciler.reconcile_changes

      cursor = Studio::Billing::SyncCursor.find_by!(name: "subscription_events")
      assert_equal "evt_3", cursor.last_event_id
      assert_equal NOW, cursor.checked_at
    end
  end

  test "#reconcile_changes raises when the cursor is older than Stripe keeps events" do
    travel_to NOW do
      Studio::Billing::SyncCursor.create!(name: "subscription_events", checked_at: 31.days.ago)

      assert_raises(Studio::Billing::Reconciler::CursorExpiredError) { reconciler.reconcile_changes }
    end
  end

  test "#reconcile_all syncs every subscription and resets the cursor" do
    Studio::Billing::SyncCursor.create!(name: "subscription_events", checked_at: 40.days.ago)
    client.v1.subscriptions.stubs(:list).returns(stripe_list(stripe_subscription))

    assert_equal 1, reconciler.reconcile_all
    assert_equal 1, Studio::Billing::Subscription.count
    assert_equal 0, Studio::Billing::SyncCursor.count
  end

  test "#reconcile_changes reports a subscription that fails and still moves the cursor" do
    travel_to NOW do
      Studio::Billing::SyncCursor.create!(name: "subscription_events", last_event_id: "evt_old", checked_at: 1.hour.ago)
      client.v1.events.stubs(:list).returns(stripe_list(event("evt_2", "sub_bad", 2), event("evt_3", "sub_1", 3)))
      client.v1.subscriptions.stubs(:retrieve).with("sub_bad").raises(Stripe::APIError.new("boom"))
      client.v1.subscriptions.stubs(:retrieve).with("sub_1").returns(stripe_subscription)
      Rails.error.expects(:report).with(instance_of(Stripe::APIError), has_entry(handled: true))

      reconciler.reconcile_changes

      assert_equal ["sub_1"], Studio::Billing::Subscription.pluck(:stripe_subscription_id)
      assert_equal "evt_3", Studio::Billing::SyncCursor.find_by!(name: "subscription_events").last_event_id
    end
  end

  test "#reconcile_all reports a subscription without an organization and carries on" do
    client.v1.subscriptions.stubs(:list).returns(stripe_list(
      stripe_subscription(id: "sub_orphan", organization: nil, customer: "cus_unknown"),
      stripe_subscription(id: "sub_2")
    ))
    Rails.error.expects(:report).with(instance_of(Studio::Billing::OrganizationNotFoundError), has_entry(handled: true))

    reconciler.reconcile_all

    assert_equal ["sub_2"], Studio::Billing::Subscription.pluck(:stripe_subscription_id)
  end

  private

  def reconciler
    Studio::Billing::Reconciler.new(client: client)
  end

  def event(id, subscription_id, created)
    stripe_object(id: id, object: "event", created: created, data: {object: {id: subscription_id}})
  end
end
