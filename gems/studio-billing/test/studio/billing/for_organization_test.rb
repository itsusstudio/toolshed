require "test_helper"

class Studio::Billing::ForOrganizationTest < StudioBillingTestCase
  test "#update_stripe_email_address sends the billing email address to the Stripe customer" do
    organization.update!(stripe_customer_id: "cus_1")
    client.v1.customers.expects(:update).with("cus_1", {email: "owner@example.test"})

    organization.update_stripe_email_address
  end

  test "#update_stripe_email_address does nothing for an organization that never paid" do
    client.v1.customers.expects(:update).never

    organization.update_stripe_email_address
  end

  test "#record_stripe_customer never replaces a different customer" do
    organization.update!(stripe_customer_id: "cus_1")

    assert_raises(Studio::Billing::StripeCustomerMismatchError) { organization.record_stripe_customer("cus_2") }
    assert_equal "cus_1", organization.reload.stripe_customer_id
  end
end
