module Studio
  module Billing
    class Catalog
      class Error < StandardError; end

      INTERVALS = ["month", "year"].freeze
      UNLIMITED = "unlimited"
      TAX_BEHAVIORS = ["inclusive", "exclusive"].freeze
      BRANDING_REQUIRED = ["display_name", "background_color", "button_color"].freeze
      BRANDING_OPTIONAL = ["border_style", "font_family", "icon_url", "logo_url"].freeze
      BORDER_STYLES = ["rectangular", "rounded", "pill"].freeze
      HEX_COLOR = /\A#(\h{3}|\h{6})\z/

      Plan = Data.define(:code, :name, :description, :legacy, :entitlements_of, :features, :limits, :prices) do
        def legacy? = legacy
        def free? = prices.empty?
      end

      Price = Data.define(:lookup_key, :plan_code, :interval, :amounts) do
        def amount(currency) = amounts[currency.to_s.downcase]
        def base_currency = amounts.keys.first
        def unit_amounts = amounts.transform_values(&:cents)
        def base_unit_amount = unit_amounts.fetch(base_currency)
      end

      attr_reader :plans, :default_plan_code, :tax_behavior, :tax_code, :branding, :portal

      class << self
        def load(path)
          new(YAML.safe_load_file(path, aliases: true) || {})
        end
      end

      def initialize(data)
        data = data.deep_stringify_keys
        tax = data["tax"] || {}

        @plans = Array(data["plans"]).map { build_plan(it) }.freeze
        @default_plan_code = data["default_plan"]
        @tax_behavior = tax["behavior"] || "inclusive"
        @tax_code = tax["code"]
        @branding = (data["branding"] || {}).transform_values(&:to_s).freeze
        @portal = (data["portal"] || {}).deep_symbolize_keys.freeze
        validate!
      end

      def prices
        plans.flat_map(&:prices)
      end

      def find_plan(code)
        plans.find { it.code == code.to_s }
      end

      def find_price(lookup_key)
        prices.find { it.lookup_key == lookup_key.to_s }
      end

      def checkout_branding_settings
        settings = branding.slice("display_name", "background_color", "button_color", "border_style", "font_family")
        settings["icon"] = {type: "url", url: branding["icon_url"]} if branding["icon_url"]
        settings["logo"] = {type: "url", url: branding["logo_url"]} if branding["logo_url"]
        settings.symbolize_keys
      end

      def feature_names
        plans.flat_map(&:features).uniq
      end

      def limit_names
        plans.flat_map { it.limits.keys }.uniq
      end

      private

      def build_plan(attributes)
        code = attributes["code"]
        raise Error, "studio-billing: every plan needs a code" if code.blank?
        raise Error, "studio-billing: plan #{code} needs a name" if attributes["name"].blank?

        Plan.new(
          code: code,
          name: attributes["name"],
          description: attributes["description"],
          legacy: attributes["legacy"] == true,
          entitlements_of: attributes["entitlements_of"],
          features: Array(attributes["features"]).map(&:to_s).freeze,
          limits: build_limits(code, attributes["limits"] || {}),
          prices: Array(attributes["prices"]).map { build_price(it, plan_code: code) }.freeze
        )
      end

      def build_limits(plan_code, limits)
        limits.to_h do |name, value|
          next [name.to_s, nil] if value == UNLIMITED
          next [name.to_s, value] if value.is_a?(Integer) && !value.negative?

          raise Error, "studio-billing: plan #{plan_code} limit #{name} is a whole number or unlimited, " \
            "not #{value.inspect}"
        end.freeze
      end

      def build_price(attributes, plan_code:)
        lookup_key = attributes["lookup_key"]
        raise Error, "studio-billing: a price on plan #{plan_code} has no lookup_key" if lookup_key.blank?

        amounts = (attributes["amounts"] || {}).to_h do |currency, amount|
          [currency.to_s.downcase, build_money(lookup_key, currency, amount)]
        end
        raise Error, "studio-billing: price #{lookup_key} needs at least one amount" if amounts.empty?

        Price.new(lookup_key: lookup_key, plan_code: plan_code, interval: attributes["interval"].to_s,
          amounts: amounts.freeze)
      end

      def build_money(lookup_key, currency, amount)
        if !Money::Currency.find(currency.to_s)
          raise Error, "studio-billing: #{lookup_key} currency #{currency.inspect} isn't an ISO currency code"
        end

        value = BigDecimal(amount.to_s)
        money = Money.from_amount(value, currency.to_s)
        if money.to_d != value
          raise Error, "studio-billing: #{lookup_key} #{currency} amount #{amount} has more decimal places " \
            "than #{money.currency.iso_code} allows"
        end
        money
      rescue ArgumentError
        raise Error, "studio-billing: price #{lookup_key} has an amount that isn't a number"
      end

      def validate!
        validate_unique(plans.map(&:code), "plan codes")
        validate_unique(prices.map(&:lookup_key), "lookup keys")

        if default_plan_code && !find_plan(default_plan_code)
          raise Error, "studio-billing: default_plan #{default_plan_code} isn't a plan"
        end

        if !TAX_BEHAVIORS.include?(tax_behavior)
          raise Error, "studio-billing: tax behavior is inclusive or exclusive, not #{tax_behavior.inspect}"
        end

        validate_branding
        plans.each { validate_entitlements_of(it) }
        validate_same_limits
        prices.each { validate_price(it) }
      end

      def validate_branding
        missing = BRANDING_REQUIRED.select { branding[it].blank? }
        if missing.any?
          raise Error, "studio-billing: branding in config/billing.yml needs #{missing.join(", ")}; " \
            "Checkout uses it on every session"
        end

        unknown = branding.keys - BRANDING_REQUIRED - BRANDING_OPTIONAL
        raise Error, "studio-billing: branding doesn't take #{unknown.join(", ")}" if unknown.any?

        ["background_color", "button_color"].each do |key|
          if !branding[key].match?(HEX_COLOR)
            raise Error, "studio-billing: branding #{key} is a hex colour like #1f1f1f, not #{branding[key].inspect}"
          end
        end

        if branding["border_style"] && !BORDER_STYLES.include?(branding["border_style"])
          raise Error, "studio-billing: branding border_style is one of #{BORDER_STYLES.join(", ")}"
        end

        ["icon_url", "logo_url"].each do |key|
          next if !branding[key] || branding[key].start_with?("https://")

          raise Error, "studio-billing: branding #{key} must be an https URL"
        end
      end

      def validate_entitlements_of(plan)
        return if !plan.entitlements_of

        source = find_plan(plan.entitlements_of)
        if !source || source.entitlements_of
          raise Error, "studio-billing: plan #{plan.code} takes entitlements_of #{plan.entitlements_of}, " \
            "which must be a plan with its own features and limits"
        end

        if plan.features.any? || plan.limits.any?
          raise Error, "studio-billing: plan #{plan.code} takes entitlements_of #{plan.entitlements_of}, " \
            "so it can't list its own features or limits"
        end
      end

      def validate_same_limits
        expected = limit_names.sort
        plans.reject(&:entitlements_of).each do |plan|
          missing = expected - plan.limits.keys
          next if missing.empty?

          raise Error, "studio-billing: plan #{plan.code} doesn't set #{missing.join(", ")}; " \
            "every plan sets every limit, as a number or unlimited"
        end
      end

      def validate_price(price)
        if !INTERVALS.include?(price.interval)
          raise Error, "studio-billing: #{price.lookup_key} interval is month or year, not #{price.interval.inspect}"
        end

        price.amounts.each do |currency, amount|
          raise Error, "studio-billing: #{price.lookup_key} #{currency} amount must be above 0" if !amount.positive?
        end
      end

      def validate_unique(values, label)
        repeated = values.tally.select { |_value, count| count > 1 }.keys
        raise Error, "studio-billing: #{label} appear twice: #{repeated.join(", ")}" if repeated.any?
      end
    end
  end
end
