module Studio
  module Auth
    module SignInLimits
      RESEND_INTERVAL = 60.seconds
      MAIL_BUDGET = 5
      IP_HOURLY_LIMIT = 30

      LOCKOUT_WINDOW = 24.hours
      LOCKOUT_WRONG_CODES = 10
      LOCKOUT_DURATION = 1.hour
      APP_REVIEW_LOCKOUT_WRONG_CODES = 20

      class << self
        def locked_out?(email_address, device_digest: nil)
          failures, last_failed_at = failure_stats(email_address, device_digest)
          return false if last_failed_at.nil?
          return failures >= APP_REVIEW_LOCKOUT_WRONG_CODES if AppReviewAccounts.include?(email_address)
          return false if failures < LOCKOUT_WRONG_CODES

          last_failed_at > (LOCKOUT_DURATION * (failures - LOCKOUT_WRONG_CODES + 1)).ago
        end

        def just_locked?(email_address, device_digest: nil)
          limit = AppReviewAccounts.include?(email_address) ? APP_REVIEW_LOCKOUT_WRONG_CODES : LOCKOUT_WRONG_CODES
          failure_stats(email_address, device_digest).first == limit
        end

        def ip_over_hourly_limit?(ip_address)
          LoginCode.where(ip_address: ip_address, created_at: 1.hour.ago..).count >= IP_HOURLY_LIMIT
        end

        def mail_budget_spent?(email_address, device_digest: nil)
          scope = LoginCode.where(email_address: email_address, created_at: 1.hour.ago..)
          scope = scope.where(device_token_digest: device_digest) if device_digest
          scope.count >= MAIL_BUDGET
        end

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
