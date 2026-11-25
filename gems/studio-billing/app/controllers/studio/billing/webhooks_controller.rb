module Studio
  module Billing
    class WebhooksController < ActionController::API
      def create
        event = Webhook.verify!(payload: request.raw_post, signature: request.headers["Stripe-Signature"])

        if Webhook.handled?(event)
          ProcessStripeWebhookJob.perform_later(event_id: event.id, event_type: event.type)
        end
        head :ok
      rescue Webhook::InvalidPayloadError
        head :bad_request
      end
    end
  end
end
