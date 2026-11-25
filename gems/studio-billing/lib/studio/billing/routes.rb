module Studio
  module Billing
    module Routes
      def studio_billing
        post "billing/webhooks", to: "studio/billing/webhooks#create", as: :studio_billing_webhooks
      end
    end
  end
end
