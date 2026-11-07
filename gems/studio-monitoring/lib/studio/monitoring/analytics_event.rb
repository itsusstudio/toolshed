module Studio
  module Monitoring
    class AnalyticsEvent < ActiveRecord::Base # standard:disable Rails/ApplicationRecord -- a gem has no ApplicationRecord
      RETENTION = 60.days

      self.table_name = "analytics_events"

      validates :event_name, presence: true
    end
  end
end
