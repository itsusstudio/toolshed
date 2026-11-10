module Studio
  module Auth
    module Lockout
      class << self
        # Counted across login_codes, so asking for a fresh code does not buy
        # fresh guesses. Each failure past the limit lengthens the lock by
        # another LOCKOUT_DURATION, so one guess an hour cannot keep it going.
        #
        # A known device counts only its own failures: strangers cannot lock
        # the owner out of their laptop, and a stolen device cookie still
        # locks after LOCKOUT_WRONG_CODES guesses of its own.
        #
        # Review accounts must not lock on a reviewer's typos, but their code
        # never rotates, so they stop at a hard daily cap instead.
        def locked?(user, device_digest: nil)
          failures, last_failed_at = failure_stats(user, device_digest)
          return false if user.nil? || last_failed_at.nil?
          return failures >= APP_REVIEW_LOCKOUT_WRONG_CODES if user.app_review_account?
          return false if failures < LOCKOUT_WRONG_CODES

          last_failed_at > (LOCKOUT_DURATION * (failures - LOCKOUT_WRONG_CODES + 1)).ago
        end

        # True only for the failure that first reaches the limit, so the
        # owner gets one lock email, not one per guess.
        def just_locked?(user, device_digest: nil)
          limit = user&.app_review_account? ? APP_REVIEW_LOCKOUT_WRONG_CODES : LOCKOUT_WRONG_CODES
          failure_stats(user, device_digest).first == limit
        end

        private

        def failure_stats(user, device_digest)
          user_id = user&.id || DECOY_USER_ID
          recent = LoginCode.where(user_id: user_id).within_lockout_window
          recent = recent.where(device_token_digest: device_digest) if device_digest
          [recent.sum(:failed_attempts), recent.maximum(:failed_at)]
        end
      end
    end
  end
end
