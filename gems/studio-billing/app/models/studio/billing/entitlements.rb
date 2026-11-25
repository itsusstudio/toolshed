module Studio
  module Billing
    class Entitlements
      class UnknownNameError < StandardError; end

      attr_reader :owner, :now

      def initialize(owner, now: Time.current, catalog: Billing.catalog, config: Billing.config)
        @owner = owner
        @now = now
        @catalog = catalog
        @config = config
      end

      def plan
        @plan ||= candidate_plans.max_by { catalog.plans.index(it) }
      end

      def subscription
        @subscription ||= owner.billing_subscriptions.counting(now: now).order(current_period_end: :desc).first
      end

      def allows?(feature)
        feature = feature.to_s
        if !catalog.feature_names.include?(feature)
          raise UnknownNameError, "studio-billing: no plan lists the feature #{feature}"
        end
        return false if !plan

        source_plan.features.include?(feature)
      end

      def limit(name)
        name = known_limit!(name)
        return 0 if !plan

        base = source_plan.limits.fetch(name)
        return nil if base.nil?

        base + limit_grants.select { it.limit_name == name }.sum(&:quantity)
      end

      def unlimited?(name)
        limit(name).nil?
      end

      def used(name)
        name = known_limit!(name)
        @used ||= {}
        @used[name] ||= config.usage_counters.fetch(name).count(owner, now: now)
      end

      def over?(name)
        allowed = limit(name)
        !allowed.nil? && used(name) > allowed
      end

      private

      attr_reader :catalog, :config

      def candidate_plans
        codes = owner.billing_subscriptions.counting(now: now).pluck(:plan_code) +
          owner.billing_grants.active(now: now).of_plans.pluck(:plan_code) +
          [catalog.default_plan_code]
        codes.compact.uniq.filter_map { catalog.find_plan(it) }
      end

      def source_plan
        plan.entitlements_of ? catalog.find_plan(plan.entitlements_of) : plan
      end

      def limit_grants
        @limit_grants ||= owner.billing_grants.active(now: now).of_limits.to_a
      end

      def known_limit!(name)
        name = name.to_s
        raise UnknownNameError, "studio-billing: no plan sets the limit #{name}" if !catalog.limit_names.include?(name)

        name
      end
    end
  end
end
