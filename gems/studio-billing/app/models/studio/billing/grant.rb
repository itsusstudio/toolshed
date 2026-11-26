module Studio
  module Billing
    class Grant < ActiveRecord::Base # standard:disable Rails/ApplicationRecord -- a gem has no ApplicationRecord
      self.table_name = "billing_grants"

      belongs_to :organization
      belongs_to :granted_by, class_name: "User", optional: true

      validates :reason, presence: true
      validates :quantity, numericality: {only_integer: true, greater_than: 0}, if: :limit_name?
      validate :grants_a_plan_or_a_limit, on: :create

      scope :active, ->(now: Time.current) {
        where(revoked_at: nil)
          .where(arel_table[:starts_at].eq(nil).or(arel_table[:starts_at].lteq(now)))
          .where(arel_table[:expires_at].eq(nil).or(arel_table[:expires_at].gt(now)))
      }
      scope :of_plans, -> { where.not(plan_code: nil) }
      scope :of_limits, -> { where.not(limit_name: nil) }

      def revoke!(now: Time.current)
        update!(revoked_at: now)
      end

      private

      def grants_a_plan_or_a_limit
        catalog = Billing.catalog

        if plan_code.present? == limit_name.present?
          errors.add(:base, "grants either a plan_code or a limit_name with a quantity")
        elsif plan_code.present? && !catalog.find_plan(plan_code)
          errors.add(:plan_code, "isn't a plan in config/billing.yml")
        elsif limit_name.present? && !catalog.limit_names.include?(limit_name)
          errors.add(:limit_name, "isn't a limit in config/billing.yml")
        end
      end
    end
  end
end
