module Studio
  module Auth
    module Lockout
      class << self
        # Counted across challenges, so asking for a fresh code does not buy
        # fresh guesses. Each failure past the limit lengthens the lock by
        # another LOCK_DURATION, so one guess an hour cannot keep it going.
        #
        # A known device counts only its own failures: strangers cannot lock
        # the owner out of their laptop, and a stolen device cookie still
        # locks after FAILURE_LIMIT guesses of its own.
        #
        # Review accounts must not lock on a reviewer's typos, but their code
        # never rotates, so they stop at a hard daily cap instead.
        def locked?(user, device_digest: nil)
          failures, last_failed_at = failure_stats(user, device_digest)
          return false if user.nil? || last_failed_at.nil?
          return failures >= REVIEW_ACCOUNT_FAILURE_LIMIT if user.review_account?
          return false if failures < FAILURE_LIMIT

          last_failed_at > (LOCK_DURATION * (failures - FAILURE_LIMIT + 1)).ago
        end

        # True only for the failure that first reaches the limit, so the
        # owner gets one lock email, not one per guess.
        def just_locked?(user, device_digest: nil)
          limit = user&.review_account? ? REVIEW_ACCOUNT_FAILURE_LIMIT : FAILURE_LIMIT
          failure_stats(user, device_digest).first == limit
        end

        private

        # A missing user queries id 0, never IS NULL: decoys then cost the
        # same as a real address and don't sum every decoy row.
        def failure_stats(user, device_digest)
          recent = LoginChallenge.where(user_id: user&.id || 0).within_failure_window
          recent = recent.where(device_token_digest: device_digest) if device_digest
          [recent.sum(:failed_attempts), recent.maximum(:failed_at)]
        end
      end
    end
  end
end
