module Studio
  module Billing
    class SyncCursor < ActiveRecord::Base # standard:disable Rails/ApplicationRecord -- a gem has no ApplicationRecord
      self.table_name = "billing_sync_cursors"

      validates :name, presence: true, uniqueness: true
      validates :checked_at, presence: true

      class << self
        def for(name)
          find_or_create_by!(name: name) { it.checked_at = Time.current }
        end

        def reset(name)
          where(name: name).delete_all
        end
      end
    end
  end
end
