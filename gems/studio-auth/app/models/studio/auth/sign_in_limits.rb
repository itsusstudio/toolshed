module Studio
  module Auth
    # How often an address or IP may ask for codes and guess them. Answers
    # questions only; LoginCode requests and verifications act on them.
    module SignInLimits
      RESEND_INTERVAL = 60.seconds
      RESEND_COOLDOWN = 30.seconds
      MAIL_BUDGET = 5
      IP_HOURLY_LIMIT = 30

      LOCKOUT_WINDOW = 24.hours
      LOCKOUT_WRONG_CODES = 10
      LOCKOUT_DURATION = 1.hour
      APP_REVIEW_LOCKOUT_WRONG_CODES = 20

      class << self
        # Counted across codes, so asking for a fresh code does not buy
        # fresh guesses. Each failure past the limit lengthens the lock by
        # another LOCKOUT_DURATION, so one guess an hour cannot keep it going.
        #
        # A known device counts only its own failures: strangers cannot lock
        # the owner out of their laptop, and a stolen device cookie still
        # locks after LOCKOUT_WRONG_CODES guesses of its own.
        #
        # Review accounts must not lock on a reviewer's typos, but their code
        # never rotates, so they stop at a hard daily cap instead.
        def locked_out?(email_address, device_digest: nil)
          failures, last_failed_at = failure_stats(email_address, device_digest)
          return false if last_failed_at.nil?
          return failures >= APP_REVIEW_LOCKOUT_WRONG_CODES if AppReviewAccounts.include?(email_address)
          return false if failures < LOCKOUT_WRONG_CODES

          last_failed_at > (LOCKOUT_DURATION * (failures - LOCKOUT_WRONG_CODES + 1)).ago
        end

        # True only for the failure that first reaches the limit, so the
        # owner gets one lock email, not one per guess.
        def just_locked?(email_address, device_digest: nil)
          limit = AppReviewAccounts.include?(email_address) ? APP_REVIEW_LOCKOUT_WRONG_CODES : LOCKOUT_WRONG_CODES
          failure_stats(email_address, device_digest).first == limit
        end

        # Backs up the cache-held rate limits; this one counts in the
        # primary database and fails closed.
        def ip_over_hourly_limit?(ip_address)
          LoginCode.where(ip_address: ip_address, created_at: 1.hour.ago..).count >= IP_HOURLY_LIMIT
        end

        # A known device has its own budget, so a stranger filling the
        # owner's inbox can't stop the owner's own laptop from getting codes.
        def mail_budget_spent?(email_address, device_digest: nil)
          scope = LoginCode.where(email_address: email_address, created_at: 1.hour.ago..)
          scope = scope.where(device_token_digest: device_digest) if device_digest
          scope.count >= MAIL_BUDGET
        end

        # A fresh code on "Send a new code" waits this long after the last
        # one, so a run of clicks can't spend the mail budget in seconds.
        def resend_too_soon?(login_code)
          login_code.created_at > RESEND_COOLDOWN.ago
        end

        # The code still inside the resend window, which a second request
        # from the same browser gets back instead of a new one.
        def code_in_resend_window(email_address)
          LoginCode.live.where(email_address: email_address)
            .where(failed_attempts: ...LoginCode::MAX_ATTEMPTS)
            .where(created_at: RESEND_INTERVAL.ago..).order(:created_at).last
        end

        private

        def failure_stats(email_address, device_digest)
          recent = LoginCode.where(email_address: email_address).within_lockout_window
          recent = recent.where(device_token_digest: device_digest) if device_digest
          [recent.sum(:failed_attempts), recent.maximum(:failed_at)]
        end
      end
    end
  end
end
