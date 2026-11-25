module Studio
  module Billing
    class Sync
      Change = Data.define(:action, :subject, :detail, :perform) do
        def to_s = "#{action.to_s.ljust(7)} #{subject}: #{detail}"
        def note? = action == :note
        def by_hand? = action == :by_hand
      end

      Result = Data.define(:changes, :webhook_secret)

      DEFAULT_PORTAL_FEATURES = {
        customer_update: {enabled: true, allowed_updates: ["email", "address", "name"]},
        invoice_history: {enabled: true},
        payment_method_update: {enabled: true},
        subscription_cancel: {enabled: true, mode: "at_period_end"},
        subscription_update: {
          enabled: true,
          default_allowed_updates: ["price"],
          proration_behavior: "always_invoice",
          schedule_at_period_end: {conditions: [{type: "decreasing_item_amount"}]}
        }
      }.freeze

      def initialize(catalog: Billing.catalog, config: Billing.config, client: Billing.client)
        @catalog = catalog
        @config = config
        @client = client
      end

      def changes
        @changes ||= begin
          prices = price_changes
          prices_moving = prices.any? { [:create, :replace].include?(it.action) }
          product_changes + prices + orphan_price_notes + portal_changes(prices_moving:) + webhook_changes
        end
      end

      def in_sync?
        changes.all?(&:note?)
      end

      def apply!
        webhook_secret = nil
        changes.each do |change|
          next if change.note? || change.by_hand?

          outcome = change.perform.call
          webhook_secret = outcome.secret if outcome.respond_to?(:secret) && outcome.secret.present?
        end
        Result.new(changes: changes, webhook_secret: webhook_secret)
      end

      private

      attr_reader :catalog, :config, :client

      def product_changes
        catalog.plans.filter_map do |plan|
          next if plan.free?

          wanted = {
            name: "#{config.product_name} #{plan.name}",
            description: plan.description,
            tax_code: catalog.tax_code,
            active: true
          }.compact
          existing = retrieve_product(plan.code)

          if !existing
            next change(:create, "product #{plan.code}", wanted[:name]) do
              client.v1.products.create({id: plan.code, **wanted})
            end
          end

          differences = wanted.select { |field, value| stripe_value(existing, field) != value }
          next if differences.empty?

          change(:update, "product #{plan.code}", differences.keys.join(", ")) do
            client.v1.products.update(plan.code, differences)
          end
        end
      end

      def price_changes
        catalog.prices.filter_map do |price|
          plan = catalog.find_plan(price.plan_code)
          existing = client.v1.prices.list({
            lookup_keys: [price.lookup_key], limit: 1, expand: ["data.currency_options"]
          }).data.first

          if !existing
            next change(:create, "price #{price.lookup_key}", describe(price.unit_amounts, price.interval)) do
              create_price(price)
            end
          end

          if !price_matches?(existing, price)
            was = describe(stripe_unit_amounts(existing), existing.recurring&.interval)
            now = describe(price.unit_amounts, price.interval)
            next change(:replace, "price #{price.lookup_key}",
              "#{was} -> #{now}; existing subscriptions keep the old price") do
              create_price(price, transfer_lookup_key: true)
              client.v1.prices.update(existing.id, {active: false})
            end
          end

          if !plan.legacy? && existing.product != plan.code
            next change(:note, "price #{price.lookup_key}",
              "lives on product #{existing.product}, not #{plan.code}; left as is")
          end

          if !existing.active
            change(:update, "price #{price.lookup_key}", "archived, make active") do
              client.v1.prices.update(existing.id, {active: true})
            end
          end
        end
      end

      def orphan_price_notes
        known_lookup_keys = catalog.prices.map(&:lookup_key)

        catalog.plans.reject(&:free?).flat_map do |plan|
          next [] if !retrieve_product(plan.code)

          client.v1.prices.list({product: plan.code, active: true, limit: 100}).auto_paging_each.filter_map do |price|
            next if known_lookup_keys.include?(price.lookup_key)

            change(:note, "price #{price.id}",
              "active on product #{plan.code} without a lookup key in billing.yml; " \
              "archive it in the Dashboard if no subscription uses it")
          end
        end
      end

      def portal_changes(prices_moving:)
        configuration_id = config.portal_configuration_id
        if configuration_id.blank?
          return [change(:by_hand, "customer portal",
            "save the customer portal settings once in the Stripe Dashboard, then set c.portal_configuration_id " \
            "to its bpc_ ID")]
        end

        live = client.v1.billing_portal.configurations.retrieve(configuration_id).to_hash
        planned = portal_params_or_nil
        return [] if planned && !prices_moving && within?(planned, live)

        [change(:update, "customer portal #{configuration_id}", "features and plans from billing.yml") do
          client.v1.billing_portal.configurations.update(configuration_id, portal_params)
        end]
      end

      def webhook_changes
        if config.webhook_url.blank?
          return [change(:note, "webhook endpoint", "c.webhook_url not set; skipped")]
        end

        existing = client.v1.webhook_endpoints.list({limit: 100}).data.find { it.url == config.webhook_url }
        events = config.webhook_events.sort

        if !existing
          return [change(:create, "webhook endpoint", "#{config.webhook_url} (#{events.size} events)") do
            client.v1.webhook_endpoints.create({
              url: config.webhook_url,
              enabled_events: events,
              api_version: config.api_version,
              description: "Managed by studio-billing"
            })
          end]
        end

        changes = []
        if existing.enabled_events.sort != events
          changes << change(:update, "webhook endpoint", "events -> #{events.join(", ")}") do
            client.v1.webhook_endpoints.update(existing.id, {enabled_events: events})
          end
        end

        if existing.api_version.present? && existing.api_version != config.api_version
          changes << change(:note, "webhook endpoint",
            "sends API version #{existing.api_version}, app uses #{config.api_version}; " \
            "add a new endpoint to change it")
        end
        changes
      end

      def portal_params
        products = switchable_plans.map do |plan|
          {product: plan.code, prices: plan.prices.map { Prices.id_for(it.lookup_key, client: client) }}
        end

        features = DEFAULT_PORTAL_FEATURES.deep_merge(catalog.portal[:features] || {})
        if features.dig(:subscription_update, :enabled)
          features[:subscription_update][:products] = products
        end

        {business_profile: catalog.portal[:business_profile], features: features}.compact
      end

      def portal_params_or_nil
        portal_params
      rescue Prices::NotFoundError
        nil
      end

      def within?(planned, live)
        case planned
        when Hash
          live.is_a?(Hash) && planned.all? { |key, value| within?(value, live[key.to_sym]) }
        when Array
          live.is_a?(Array) && planned.size == live.size &&
            planned.all? { |value| live.any? { within?(value, it) } }
        else
          planned == live
        end
      end

      def switchable_plans
        catalog.plans.reject { it.free? || it.legacy? }
      end

      def retrieve_product(id)
        @products ||= {}
        return @products[id] if @products.key?(id)

        @products[id] = client.v1.products.retrieve(id)
      rescue Stripe::InvalidRequestError => e
        raise if e.code != "resource_missing"

        @products[id] = nil
      end

      def create_price(price, transfer_lookup_key: false)
        other_currencies = price.unit_amounts.except(price.base_currency).transform_values do |unit_amount|
          {unit_amount: unit_amount, tax_behavior: catalog.tax_behavior}
        end

        client.v1.prices.create({
          product: price.plan_code,
          currency: price.base_currency,
          unit_amount: price.base_unit_amount,
          currency_options: other_currencies.presence,
          recurring: {interval: price.interval},
          lookup_key: price.lookup_key,
          transfer_lookup_key: transfer_lookup_key,
          tax_behavior: catalog.tax_behavior
        }.compact)
      end

      def price_matches?(existing, price)
        existing.currency == price.base_currency &&
          existing.recurring&.interval == price.interval &&
          stripe_unit_amounts(existing) == price.unit_amounts.sort.to_h &&
          stripe_tax_behaviors(existing).all?(catalog.tax_behavior)
      end

      def stripe_tax_behaviors(existing)
        options = existing.to_hash[:currency_options] || {}
        [existing.try(:tax_behavior), *options.values.pluck(:tax_behavior)].compact.presence || [nil]
      end

      def stripe_unit_amounts(existing)
        options = existing.to_hash[:currency_options] || {}
        amounts = options.to_h { |currency, option| [currency.to_s, option[:unit_amount]] }
        amounts.merge(existing.currency => existing.unit_amount).sort.to_h
      end

      def stripe_value(existing, field)
        existing.respond_to?(field) ? existing.public_send(field) : nil
      end

      def describe(unit_amounts, interval)
        amounts = unit_amounts.map do |currency, cents|
          "#{currency.upcase} #{Money.new(cents, currency).to_d.to_s("F")}"
        end
        "#{amounts.join(", ")}/#{interval}"
      end

      def change(action, subject, detail, &perform)
        Change.new(action: action, subject: subject, detail: detail, perform: perform)
      end
    end
  end
end
