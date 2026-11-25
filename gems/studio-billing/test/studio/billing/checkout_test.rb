require "test_helper"

class ShopWithoutEmailAddress < ApplicationRecord
  self.table_name = "organizations"
  include Studio::Billing::ForOwner
end

class Studio::Billing::CheckoutTest < StudioBillingTestCase
  setup do
    Studio::Billing::Prices.stubs(:id_for).with("team_yearly", client: client).returns("price_ty")
  end

  test "#session_params for a first purchase sends the email address, owner and branding" do
    params = checkout.session_params(owner: organization, lookup_key: "team_yearly", return_url: return_url)

    assert_equal "subscription", params[:mode]
    assert_equal [{price: "price_ty", quantity: 1}], params[:line_items]
    assert_equal "owner@example.test", params[:customer_email]
    assert_nil params[:customer]
    assert_equal organization.billing_global_id, params[:client_reference_id]
    assert_equal organization.billing_global_id,
      params.dig(:subscription_data, :metadata, Studio::Billing::OWNER_METADATA_KEY)
    assert_equal "Workbench", params.dig(:branding_settings, :display_name)
    assert_equal return_url, params[:return_url]
    assert_equal({enabled: false}, params[:automatic_tax])
    refute params.key?(:payment_method_types), "Checkout picks payment methods from the Dashboard"
  end

  test "#session_params raises when the owner model doesn't define billing_email_address" do
    error = assert_raises(NotImplementedError) do
      checkout.session_params(owner: ShopWithoutEmailAddress.create!, lookup_key: "team_yearly",
        return_url: return_url)
    end
    assert_match "billing_email_address", error.message
  end

  test "#session_params reuses the owner's Stripe customer and leaves out the email address" do
    organization.update!(stripe_customer_id: "cus_known")

    params = checkout.session_params(owner: organization, lookup_key: "team_yearly", return_url: return_url)

    assert_equal "cus_known", params[:customer]
    assert_nil params[:customer_email]
  end

  test "#session_params lets Stripe collect an address from a known customer once tax is on" do
    organization.update!(stripe_customer_id: "cus_known")
    Studio::Billing.config.automatic_tax = true

    params = checkout.session_params(owner: organization, lookup_key: "team_yearly", return_url: return_url)

    assert_equal({address: "auto", name: "auto"}, params[:customer_update])
    assert_equal({enabled: true}, params[:automatic_tax])
  end

  test "#session_params passes the integration identifier when set" do
    Studio::Billing.config.integration_identifier = "workbench_signup_qhzkdmwp"

    params = checkout.session_params(owner: organization, lookup_key: "team_yearly", return_url: return_url)

    assert_equal "workbench_signup_qhzkdmwp", params[:integration_identifier]
  end

  test "#session_params refuses a legacy plan's price" do
    assert_raises(Studio::Billing::Checkout::NotForSaleError) do
      checkout.session_params(owner: organization, lookup_key: "simple_yearly", return_url: return_url)
    end
  end

  test "#session_params refuses a lookup key that isn't in the catalog" do
    assert_raises(Studio::Billing::Checkout::NotForSaleError) do
      checkout.session_params(owner: organization, lookup_key: "pro_yearly", return_url: return_url)
    end
  end

  test "#session_params refuses an owner who already has a subscription that counts" do
    subscribe(organization)

    assert_raises(Studio::Billing::Checkout::AlreadySubscribedError) do
      checkout.session_params(owner: organization, lookup_key: "team_yearly", return_url: return_url)
    end
  end

  test "#complete records the customer and the subscription" do
    client.v1.checkout.sessions.stubs(:retrieve).with("cs_1").returns(stripe_object(
      id: "cs_1", object: "checkout.session", status: "complete", customer: "cus_new", subscription: "sub_1",
      client_reference_id: organization.billing_global_id
    ))
    client.v1.subscriptions.stubs(:retrieve).with("sub_1").returns(stripe_subscription(customer: "cus_new"))

    completion = checkout.complete(session_id: "cs_1")

    assert_predicate completion, :complete?
    assert_equal "sub_1", completion.subscription.stripe_subscription_id
    assert_equal "cus_new", organization.reload.stripe_customer_id
  end

  test "#complete for an open session syncs nothing" do
    client.v1.checkout.sessions.stubs(:retrieve).returns(stripe_object(id: "cs_1", status: "open"))
    client.v1.subscriptions.expects(:retrieve).never

    completion = checkout.complete(session_id: "cs_1")

    refute_predicate completion, :complete?
    assert_nil completion.subscription
  end

  private

  def checkout
    Studio::Billing::Checkout.new(client: client)
  end

  def return_url
    "https://app.example.test/billing/return?session_id={CHECKOUT_SESSION_ID}"
  end
end
