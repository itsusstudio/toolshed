require "test_helper"

class Studio::Billing::ForOwnerTest < StudioBillingTestCase
  test "#update_stripe_email_address sends the owner's current address to its Stripe customer" do
    organization.update!(stripe_customer_id: "cus_1")
    client.v1.customers.expects(:update).with("cus_1", {email: "owner@example.test"})

    organization.update_stripe_email_address
  end

  test "#update_stripe_email_address does nothing for an owner who never paid" do
    client.v1.customers.expects(:update).never

    organization.update_stripe_email_address
  end
end
