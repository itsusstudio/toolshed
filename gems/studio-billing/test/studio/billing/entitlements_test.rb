require "test_helper"

class Studio::Billing::EntitlementsTest < StudioBillingTestCase
  NOW = Time.zone.local(2026, 11, 25, 12)

  test "#plan is the default plan with no subscription or grant" do
    travel_to(NOW) { assert_equal "free", organization.entitlements.plan.code }
  end

  test "#plan is the subscribed plan while the subscription is active" do
    travel_to NOW do
      subscribe(organization)

      assert_equal "team", organization.entitlements.plan.code
    end
  end

  test "#plan keeps a past due subscription within the grace period" do
    travel_to NOW do
      subscribe(organization, status: "past_due", period_end: 2.days.ago)

      assert_equal "team", organization.entitlements.plan.code
    end
  end

  test "#plan falls to the default plan once the grace period is over" do
    travel_to NOW do
      subscribe(organization, status: "past_due", period_end: 4.days.ago)

      assert_equal "free", organization.entitlements.plan.code
    end
  end

  test "#plan ignores a canceled subscription" do
    travel_to NOW do
      subscribe(organization, status: "canceled")

      assert_equal "free", organization.entitlements.plan.code
    end
  end

  test "#plan gives a plan grant until it expires" do
    travel_to NOW do
      organization.billing_grants.create!(reason: "trial", plan_code: "team", expires_at: 14.days.from_now)

      assert_equal "team", organization.entitlements.plan.code
      travel 15.days
      assert_equal "free", organization.entitlements.plan.code
    end
  end

  test "#plan ignores a revoked grant" do
    travel_to NOW do
      organization.billing_grants.create!(reason: "staff", plan_code: "team").revoke!

      assert_equal "free", organization.entitlements.plan.code
    end
  end

  test "#plan picks the plan listed last when several apply" do
    travel_to NOW do
      subscribe(organization, lookup_key: "team_yearly")
      organization.billing_grants.create!(reason: "comp", plan_code: "free")

      assert_equal "team", organization.entitlements.plan.code
    end
  end

  test "a legacy plan with entitlements_of gives that plan's features and limits" do
    travel_to NOW do
      subscribe(organization, lookup_key: "simple_yearly")
      entitlements = organization.entitlements

      assert_equal "simple", entitlements.plan.code
      assert entitlements.allows?(:texts), "simple takes team's texts feature"
      assert_equal 200, entitlements.limit(:new_jobs)
    end
  end

  test "#allows? is false for a feature the plan doesn't list" do
    travel_to(NOW) { refute organization.entitlements.allows?(:texts), "free has no texts" }
  end

  test "#limit is nil for unlimited and #over? is never true for it" do
    travel_to NOW do
      subscribe(organization)
      organization.update!(locations_count: 50)

      assert organization.entitlements.unlimited?(:locations), "team has unlimited locations"
      refute organization.entitlements.over?(:locations), "unlimited is never over"
    end
  end

  test "#limit adds active limit grants to the plan's limit" do
    travel_to NOW do
      organization.billing_grants.create!(reason: "pack", limit_name: "new_jobs", quantity: 30)
      organization.billing_grants.create!(reason: "old pack", limit_name: "new_jobs", quantity: 5,
        expires_at: 1.day.ago)

      assert_equal 50, organization.entitlements.limit(:new_jobs)
    end
  end

  test "#used counts the calendar month in the app's time zone" do
    travel_to NOW do
      organization.jobs.create!(created_at: Time.zone.local(2026, 11, 1, 0, 30))
      organization.jobs.create!(created_at: Time.zone.local(2026, 10, 31, 23, 30))

      assert_equal 1, organization.entitlements.used(:new_jobs)
    end
  end

  test "#over? is true once used passes the limit" do
    travel_to NOW do
      21.times { organization.jobs.create! }

      assert organization.entitlements.over?(:new_jobs), "21 new jobs is over free's 20"
    end
  end

  test "a feature or limit name no plan lists raises" do
    assert_raises(Studio::Billing::Entitlements::UnknownNameError) { organization.entitlements.allows?(:txts) }
    assert_raises(Studio::Billing::Entitlements::UnknownNameError) { organization.entitlements.limit(:new_job) }
  end

  test "#subscription is the counting subscription" do
    travel_to NOW do
      subscription = subscribe(organization)

      assert_equal subscription, organization.entitlements.subscription
    end
  end
end
