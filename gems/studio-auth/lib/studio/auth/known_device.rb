module Studio
  module Auth
    class KnownDevice < ActiveRecord::Base # standard:disable Rails/ApplicationRecord -- a gem has no ApplicationRecord
      include UserReference

      validates :user_id, presence: true

      # A device unused for this long stops skipping the lockout.
      scope :trusted, -> { where(last_seen_at: SESSION_ABSOLUTE_TIMEOUT.ago..) }

      class << self
        def digest_token(token)
          Secrets.digest("known_device", token)
        end
      end
    end
  end
end
