module Studio
  module Billing
    class ProcessStripeWebhookJob < ActiveJob::Base # standard:disable Rails/ApplicationJob
      class PaymentProblemError < StandardError; end

      PAYMENT_PROBLEM_EVENT = "studio_billing.payment_problem"
      SUBSCRIPTION_EVENTS = [
        "customer.subscription.created", "customer.subscription.updated", "customer.subscription.deleted"
      ].freeze
      INVOICE_EVENTS = ["invoice.paid", "invoice.payment_failed"].freeze
      PROBLEM_EVENTS = ["charge.dispute.created", "charge.refunded", "radar.early_fraud_warning.created"].freeze

      queue_as { Billing.config.queue }

      retry_on StandardError, wait: :polynomially_longer, attempts: 10
      discard_on OrganizationNotFoundError, StripeCustomerMismatchError do |_job, error|
        Rails.error.report(error, handled: true)
      end

      def perform(event_id:, event_type:)
        webhook_event = WebhookEvent.claim(stripe_event_id: event_id, event_type: event_type)
        return if !webhook_event

        event = Billing.client.v1.events.retrieve(event_id)
        webhook_event.processed!(process(event.type, event.data.object))
      end

      private

      def process(event_type, object)
        case event_type
        when *SUBSCRIPTION_EVENTS then SubscriptionSync.call(object.id)&.organization
        when *INVOICE_EVENTS then sync_invoice(object)
        when "checkout.session.completed" then complete_checkout(object)
        when *PROBLEM_EVENTS then report_problem(event_type, object)
        end
      end

      def sync_invoice(invoice)
        stripe_subscription_id = invoice.to_hash.dig(:parent, :subscription_details, :subscription)
        return if !stripe_subscription_id

        SubscriptionSync.call(stripe_subscription_id)&.organization
      end

      def complete_checkout(session)
        return if session.mode != "subscription" || !session.subscription

        organization = Billing.find_organization(session.client_reference_id)
        organization&.record_stripe_customer(session.customer)
        SubscriptionSync.call(session.subscription)&.organization
      end

      def report_problem(event_type, object)
        charge_id = (event_type == "charge.refunded") ? object.id : object.charge
        charge = Billing.client.v1.charges.retrieve(charge_id)
        organization = Billing.organization_for_stripe_customer(charge.customer)

        ActiveSupport::Notifications.instrument(PAYMENT_PROBLEM_EVENT,
          organization: organization, event_type: event_type, stripe_object_id: object.id, stripe_charge_id: charge_id)
        Rails.error.report(
          PaymentProblemError.new("studio-billing: #{event_type} on charge #{charge_id}"),
          handled: true,
          severity: :warning,
          context: {event_type: event_type, stripe_charge_id: charge_id, organization_id: organization&.id}
        )
        organization
      end
    end
  end
end
