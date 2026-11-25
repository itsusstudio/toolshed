module Studio
  module Billing
    module ForOwner
      extend ActiveSupport::Concern

      included do
        before_destroy :ensure_stripe_will_not_charge_again, prepend: true

        has_many :billing_subscriptions, as: :owner, class_name: "Studio::Billing::Subscription", dependent: :destroy
        has_many :billing_grants, as: :owner, class_name: "Studio::Billing::Grant", dependent: :destroy
      end

      def record_stripe_customer(stripe_customer_id)
        return if stripe_customer_id.blank? || stripe_customer_id == self.stripe_customer_id

        columns = {stripe_customer_id: stripe_customer_id}
        columns[:updated_at] = Time.current if has_attribute?(:updated_at)
        update_columns(columns)
      end

      def update_stripe_email_address
        return if stripe_customer_id.blank?

        Billing.client.v1.customers.update(stripe_customer_id, {email: billing_email_address})
      end

      def cancel_billing!(at_period_end: false)
        Cancellation.new.call(self, at_period_end: at_period_end)
      end

      def entitlements
        Entitlements.new(self)
      end

      def billing_email_address
        raise NotImplementedError, "studio-billing: #{self.class.name} includes Studio::Billing::ForOwner, " \
          "so it must define billing_email_address: the address Stripe sends receipts and invoices to"
      end

      def billing_global_id
        to_global_id.to_s
      end

      private

      def ensure_stripe_will_not_charge_again
        stripe_subscription_ids = billing_subscriptions.charging_again.pluck(:stripe_subscription_id)
        return if stripe_subscription_ids.empty?

        raise BillingStillActiveError, "studio-billing: #{self.class.name} #{id} still has Stripe subscriptions " \
          "that will charge again (#{stripe_subscription_ids.join(", ")}). Call cancel_billing! before deleting it."
      end
    end
  end
end
