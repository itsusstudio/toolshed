module Studio
  module Auth
    # Keyed on the email address, so an address with no account gets the same
    # answers as one with an account; only the mail differs.
    class LoginCode < ActiveRecord::Base # standard:disable Rails/ApplicationRecord -- a gem has no ApplicationRecord
      self.ignored_columns += ["user_id"]

      Issued = Data.define(:id, :code)
      Verification = Data.define(:status, :email_address, :user) do
        def initialize(status:, email_address: nil, user: nil) = super
      end

      TTL = 10.minutes
      MAX_ATTEMPTS = 5

      validates :email_address, :code_digest, :expires_at, presence: true

      scope :live, -> { where(consumed_at: nil).where(arel_table[:expires_at].gt(Time.current)) }
      scope :within_lockout_window, -> { where(created_at: SignInLimits::LOCKOUT_WINDOW.ago..) }
      scope :purgeable, -> { where(created_at: ...SignInLimits::LOCKOUT_WINDOW.ago) }

      class << self
        def request_for(email_address:, device_cookie:, ip_address:, user_agent:,
          account_required: false, resend: false)
          email_address = TypedInput.email_address(email_address)
          return :undeliverable if Deliverability.undeliverable?(email_address)
          return :too_many_requests if SignInLimits.ip_over_hourly_limit?(ip_address)

          user = ::User.find_by(email_address: email_address)
          return :no_account if account_required && user.nil?

          device_cookie.ensure_device_token!
          known_device = device_cookie.trusted_for?(user)
          device_digest = KnownDevice.digest(device_cookie.device_token) if known_device
          app_review = AppReviewAccounts.include?(email_address)

          transaction do
            lock_address(email_address)
            # The same browser asking again (a double submit, or a retry after
            # a lost response) gets its own code back, unless it asked for a
            # new one. Another browser inside the resend window must not: it
            # could burn the first browser's attempts. A known device takes
            # over instead.
            recent = SignInLimits.code_in_resend_window(email_address)
            if recent&.from?(device_cookie)
              next Issued.new(id: recent.id, code: nil) if !resend
            elsif recent && !known_device && !app_review
              next :too_many_requests
            end
            next :too_many_requests if SignInLimits.locked_out?(email_address, device_digest: device_digest)
            if SignInLimits.mail_budget_spent?(email_address, device_digest: device_digest) && !app_review
              next :too_many_requests
            end

            issue(email_address: email_address, known_device: known_device, device_cookie: device_cookie,
              ip_address: ip_address, user_agent: user_agent)
          end
        end

        def verify(id:, code:)
          found = find_by(id: id)
          return Verification.new(status: :expired) if found.nil?

          transaction do
            lock_address(found.email_address)
            login_code = lock.find(found.id)
            # Codes issued before codes were keyed by address have none.
            next Verification.new(status: :expired) if login_code.finished? || login_code.email_address.blank?
            next Verification.new(status: :too_many_attempts) if login_code.exhausted?

            user = ::User.find_by(email_address: login_code.email_address)
            blocked = SignInLimits.locked_out?(login_code.email_address, device_digest: login_code.lockout_scope) ||
              (user && !user.can_sign_in?)
            if login_code.code_matches?(code.to_s) && !blocked
              login_code.update!(consumed_at: Time.current)
              Rails.event.notify("authentication.login_code_verified", actor_id: user&.id)
              next Verification.new(status: :verified, email_address: login_code.email_address, user: user)
            end

            record_failure(login_code, user)
            Verification.new(status: login_code.exhausted? ? :too_many_attempts : :invalid)
          end
        end

        def digest_code(code)
          Secrets.digest("login_code", code)
        end

        private

        # Serializes requests and guesses for one address, so two at once
        # can't both slip under the resend window, mail budget or lockout.
        def lock_address(email_address)
          return if !connection.adapter_name.match?(/postg/i)

          connection.execute(sanitize_sql_array(["SELECT pg_advisory_xact_lock(hashtext(?))", "studio_auth_login_code:#{email_address}"]))
        end

        def issue(email_address:, known_device:, device_cookie:, ip_address:, user_agent:)
          code = AppReviewAccounts.code_for(email_address) || Secrets.generate_code
          live.where(email_address: email_address).update_all(expires_at: Time.current)
          login_code = create!(
            email_address: email_address,
            code_digest: digest_code(code),
            expires_at: TTL.from_now, known_device: known_device,
            device_token_digest: KnownDevice.digest(device_cookie.device_token),
            ip_address: ip_address, user_agent: user_agent
          )

          SignInMailer.with(login_code: login_code, encrypted_code: Secrets.encrypt(code), locale: I18n.locale.to_s).login_code.deliver_later
          Rails.event.notify("authentication.login_code_issued")
          Issued.new(id: login_code.id, code: code)
        end

        def record_failure(login_code, user)
          login_code.update!(failed_attempts: login_code.failed_attempts + 1, failed_at: Time.current)
          just_locked = SignInLimits.just_locked?(login_code.email_address, device_digest: login_code.lockout_scope)
          Rails.event.notify("authentication.login_code_rejected", actor_id: user&.id)
          return if user.nil?

          app_review_account = user.app_review_account?
          Rails.event.notify("authentication.app_review_account_code_rejected", actor_id: user.id) if app_review_account
          return if !just_locked

          event = app_review_account ? "app_review_account_locked" : "account_locked"
          Rails.event.notify("authentication.#{event}", actor_id: user.id)
          SignInMailer.with(user: user).locked.deliver_later if !app_review_account
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
