module Studio
  module Billing
    class Subscription < ActiveRecord::Base # standard:disable Rails/ApplicationRecord -- a gem has no ApplicationRecord
      self.table_name = "billing_subscriptions"

      STATUSES = [
        "incomplete", "incomplete_expired", "trialing", "active", "past_due", "canceled", "unpaid", "paused"
      ].freeze
      COUNTING_STATUSES = ["trialing", "active", "past_due"].freeze
      ENDED_STATUSES = ["canceled", "incomplete_expired"].freeze

      belongs_to :organization

      validates :stripe_subscription_id, presence: true
      validates :stripe_subscription_id, uniqueness: true, on: :update
      validates :stripe_customer_id, :stripe_price_id, :current_period_end, :synced_at, presence: true
      validates :status, inclusion: {in: STATUSES}

      scope :not_ended, -> { where.not(status: ENDED_STATUSES) }
      scope :charging_again, -> { not_ended.where(cancel_at: nil) }
      scope :counting, ->(now: Time.current) {
        where(status: COUNTING_STATUSES, current_period_end: (now - Billing.config.grace_period)..)
      }

      class << self
        def attributes_from(stripe_subscription)
          item = stripe_subscription.items.data.min_by(&:current_period_end)
          lookup_key = item.price.lookup_key

          {
            stripe_customer_id: stripe_subscription.customer,
            stripe_price_id: item.price.id,
            lookup_key: lookup_key,
            plan_code: Billing.catalog.find_price(lookup_key)&.plan_code,
            status: stripe_subscription.status,
            current_period_end: Time.zone.at(item.current_period_end),
            cancel_at: scheduled_end(stripe_subscription, item),
            synced_at: Time.current
          }
        end

        private

        def scheduled_end(stripe_subscription, item)
          return Time.zone.at(stripe_subscription.cancel_at) if stripe_subscription.cancel_at
          return Time.zone.at(item.current_period_end) if stripe_subscription.try(:cancel_at_period_end)

          nil
        end
      end

      def counting?(now: Time.current)
        COUNTING_STATUSES.include?(status) && current_period_end >= now - Billing.config.grace_period
      end
    end
  end
end
