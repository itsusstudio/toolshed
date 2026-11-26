module Studio
  module Billing
    class WebhookEvent < ActiveRecord::Base # standard:disable Rails/ApplicationRecord -- a gem has no ApplicationRecord
      self.table_name = "billing_webhook_events"

      belongs_to :organization, optional: true

      validates :stripe_event_id, presence: true
      validates :stripe_event_id, uniqueness: true, on: :update
      validates :event_type, presence: true

      scope :processed, -> { where.not(processed_at: nil) }

      class << self
        def claim(stripe_event_id:, event_type:)
          event = create_or_find_by!(stripe_event_id: stripe_event_id) { it.event_type = event_type }
          event if !event.processed_at
        end
      end

      def processed!(organization)
        update!(organization: organization, processed_at: Time.current)
      end
    end
  end
end
