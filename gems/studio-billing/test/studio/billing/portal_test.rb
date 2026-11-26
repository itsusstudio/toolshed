require "test_helper"

class Studio::Billing::PortalTest < StudioBillingTestCase
  test "#create_session raises for an organization that has never paid" do
    assert_raises(Studio::Billing::Portal::NoCustomerError) do
      portal.create_session(organization: organization, return_url: "https://app.example.test/billing")
    end
  end

  test "#create_session opens the cancel flow on the counting subscription" do
    subscription = subscribe(organization)
    client.v1.billing_portal.sessions.expects(:create).with do |params|
      params[:customer] == "cus_#{organization.id}" &&
        params[:configuration] == "bpc_test" &&
        params.dig(:flow_data, :subscription_cancel, :subscription) == subscription.stripe_subscription_id &&
        params.dig(:flow_data, :after_completion, :redirect, :return_url) == "https://app.example.test/done"
    end

    portal.create_session(organization: organization, return_url: "https://app.example.test/billing",
      flow: :subscription_cancel, after_completion_url: "https://app.example.test/done")
  end

  test "#create_session raises without a portal configuration ID" do
    subscribe(organization)
    Studio::Billing.config.portal_configuration_id = nil

    assert_raises(Studio::Billing::Configuration::Error) do
      portal.create_session(organization: organization, return_url: "https://app.example.test/billing")
    end
  end

  test "#create_session refuses an unknown flow" do
    subscribe(organization)

    assert_raises(ArgumentError) do
      portal.create_session(organization: organization, return_url: "https://app.example.test/billing", flow: :refund)
    end
  end

  private

  def portal
    Studio::Billing::Portal.new(client: client)
  end
end
