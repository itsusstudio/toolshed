module Studio
  module Auth
    class KnownDevice < ActiveRecord::Base # standard:disable Rails/ApplicationRecord -- a gem has no ApplicationRecord
      TRUST_PERIOD = 90.days

      belongs_to :user, class_name: "::User"

      validates :device_token_digest, :last_seen_at, presence: true
      validates :device_token_digest, uniqueness: {scope: :user_id}

      scope :trusted, -> { where(last_seen_at: TRUST_PERIOD.ago..) }

      class << self
        def digest(device_token)
          Secrets.digest("known_device", device_token)
        end
      end
    end
  end
end
