module Studio
  module Auth
    # Keyed on the email address, not the user, so a sign-up code exists
    # before its account does. RequestCode and VerifyCode act on it.
    class LoginCode < ActiveRecord::Base # standard:disable Rails/ApplicationRecord -- a gem has no ApplicationRecord
      self.ignored_columns += ["user_id"]

      TTL = 10.minutes
      MAX_ATTEMPTS = 5

      validates :email_address, :code_digest, :expires_at, presence: true

      scope :live, -> { where(consumed_at: nil).where(arel_table[:expires_at].gt(Time.current)) }
      scope :within_lockout_window, -> { where(created_at: SignInLimits::LOCKOUT_WINDOW.ago..) }
      scope :purgeable, -> { where(created_at: ...SignInLimits::LOCKOUT_WINDOW.ago) }

      class << self
        def digest_code(code)
          Secrets.digest("login_code", code)
        end

        # Serializes requests and guesses for one address, so two at once
        # can't both slip under the resend window, mail budget or lockout.
        # Call inside a transaction.
        def lock_address(email_address)
          return if !connection.adapter_name.match?(/postg/i)

          key = "studio_auth_login_code:#{email_address}"
          connection.execute(sanitize_sql_array(["SELECT pg_advisory_xact_lock(hashtext(?))", key]))
        end
      end

      def lockout_scope
        device_token_digest if known_device
      end

      def finished?
        consumed_at.present? || expires_at <= Time.current
      end

      def from?(device_cookie)
        return false if device_cookie.device_token.blank? || device_token_digest.blank?

        ActiveSupport::SecurityUtils.secure_compare(device_token_digest, KnownDevice.digest(device_cookie.device_token))
      end

      def exhausted?
        failed_attempts >= MAX_ATTEMPTS
      end

      def code_matches?(code)
        Secrets.matches?(code_digest, "login_code", code)
      end
    end
  end
end
