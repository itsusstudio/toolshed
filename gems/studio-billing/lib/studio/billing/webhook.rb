module Studio
  module Billing
    module Webhook
      class InvalidPayloadError < StandardError; end

      TOLERANCE = 300

      class << self
        def verify!(payload:, signature:)
          config = Billing.config
          config.validate_webhook_config!

          Stripe::Webhook.construct_event(payload, signature, config.webhook_secret, tolerance: TOLERANCE)
        rescue JSON::ParserError, Stripe::SignatureVerificationError => e
          raise InvalidPayloadError, e.message
        end

        def handled?(event)
          Billing.config.webhook_events.include?(event.type)
        end
      end
    end
  end
end
