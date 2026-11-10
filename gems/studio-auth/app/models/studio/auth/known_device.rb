module Studio
  module Auth
    class KnownDevice < ActiveRecord::Base # standard:disable Rails/ApplicationRecord -- a gem has no ApplicationRecord
      belongs_to :user, class_name: "::User"

      scope :trusted, -> { where(last_seen_at: KNOWN_DEVICE_TRUST.ago..) }

      class << self
        def digest(device_token)
          Secrets.digest("known_device", device_token)
        end
      end
    end
  end
end
