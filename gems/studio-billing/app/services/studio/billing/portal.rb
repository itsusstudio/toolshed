module Studio
  module Billing
    class Portal
      class NoCustomerError < StandardError; end

      FLOWS = ["payment_method_update", "subscription_cancel", "subscription_update"].freeze

      def initialize(client: Billing.client)
        @client = client
      end

      def create_session(organization:, return_url:, flow: nil, after_completion_url: nil)
        stripe_customer_id = organization.stripe_customer_id
        if !stripe_customer_id
          raise NoCustomerError, "studio-billing: #{organization.id} has never paid through Stripe"
        end

        Billing.config.validate_portal_config!
        params = {
          customer: stripe_customer_id,
          configuration: Billing.config.portal_configuration_id,
          return_url: return_url
        }
        params[:flow_data] = flow_data(organization, flow.to_s, after_completion_url) if flow
        client.v1.billing_portal.sessions.create(params)
      end

      private

      attr_reader :client

      def flow_data(organization, flow, after_completion_url)
        raise ArgumentError, "studio-billing: portal flow is one of #{FLOWS.join(", ")}" if !FLOWS.include?(flow)

        data = {type: flow}
        if flow != "payment_method_update"
          subscription = organization.entitlements.subscription
          raise ArgumentError, "studio-billing: the #{flow} flow needs a subscription that counts" if !subscription

          data[flow.to_sym] = {subscription: subscription.stripe_subscription_id}
        end

        if after_completion_url
          data[:after_completion] = {type: "redirect", redirect: {return_url: after_completion_url}}
        end
        data
      end
    end
  end
end
