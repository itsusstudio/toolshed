module Studio
  module Billing
    module Prices
      class NotFoundError < StandardError; end

      class << self
        def id_for(lookup_key, client: Billing.client)
          price = client.v1.prices.list({lookup_keys: [lookup_key], active: true, limit: 1}).data.first
          if !price
            raise NotFoundError, "studio-billing: no active Stripe price has lookup key #{lookup_key.inspect}"
          end

          price.id
        end

        def lookup_key_for(price_id, client: Billing.client)
          client.v1.prices.retrieve(price_id).lookup_key
        end
      end
    end
  end
end
