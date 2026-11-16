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
      RESEND_INTERVAL = 60.seconds
      MAIL_BUDGET = 10
      IP_HOURLY_LIMIT = 30

      LOCKOUT_WINDOW = 24.hours
      LOCKOUT_WRONG_CODES = 10
      LOCKOUT_DURATION = 1.hour
      APP_REVIEW_LOCKOUT_WRONG_CODES = 20

      validates :email_address, :code_digest, :expires_at, presence: true

      scope :live, -> { where(consumed_at: nil).where(arel_table[:expires_at].gt(Time.current)) }
      scope :within_lockout_window, -> { where(created_at: LOCKOUT_WINDOW.ago..) }
      scope :purgeable, -> { where(created_at: ...LOCKOUT_WINDOW.ago) }

      class << self
        def request_for(email_address:, device_cookie:, ip_address:, user_agent:)
          email_address = TypedInput.email_address(email_address)
          return :undeliverable if Deliverability.undeliverable?(email_address)
          # Backs up the cache-held rate limits, which turn off if the cache
          # fails; this one counts in the primary database and fails closed.
          return :too_many_requests if ip_over_hourly_limit?(ip_address)

          device_cookie.ensure_device_token!
          user = ::User.find_by(email_address: email_address)
          known_device = device_cookie.trusted_for?(user)
          device_digest = KnownDevice.digest(device_cookie.device_token) if known_device
          app_review = AppReviewAccounts.include?(email_address)

          transaction do
            # The same browser asking again (a double submit, or a retry after
            # a lost response) gets its own code back. Another browser inside
            # the resend window must not: it could burn the first browser's
            # attempts. A known device takes over instead.
            recent = recent_login_code(email_address)
            next Issued.new(id: recent.id, code: nil) if recent&.from?(device_cookie)
            next :too_many_requests if recent && !known_device && !app_review
            next :too_many_requests if locked_out?(email_address, device_digest: device_digest)
            next :too_many_requests if mail_count(email_address, device_digest) >= MAIL_BUDGET && !app_review

            issue(email_address: email_address, known_device: known_device, device_cookie: device_cookie,
              ip_address: ip_address, user_agent: user_agent)
          end
        end

        def verify(id:, code:)
          found = find_by(id: id)
          return Verification.new(status: :expired) if found.nil?

          transaction do
            login_code = lock.find(found.id)
            next Verification.new(status: :expired) if login_code.finished?
            next Verification.new(status: :too_many_attempts) if login_code.exhausted?

            user = ::User.find_by(email_address: login_code.email_address)
            blocked = locked_out?(login_code.email_address, device_digest: login_code.lockout_scope) ||
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

        def digest_code(code)
          Secrets.digest("login_code", code)
        end

        private

        # True only for the failure that first reaches the limit, so the
        # owner gets one lock email, not one per guess.
        def just_locked?(email_address, device_digest: nil)
          limit = AppReviewAccounts.include?(email_address) ? APP_REVIEW_LOCKOUT_WRONG_CODES : LOCKOUT_WRONG_CODES
          failure_stats(email_address, device_digest).first == limit
        end

        def failure_stats(email_address, device_digest)
          recent = where(email_address: email_address).within_lockout_window
          recent = recent.where(device_token_digest: device_digest) if device_digest
          [recent.sum(:failed_attempts), recent.maximum(:failed_at)]
        end

        def ip_over_hourly_limit?(ip_address)
          where(ip_address: ip_address, created_at: 1.hour.ago..).count >= IP_HOURLY_LIMIT
        end

        # A known device has its own budget, so a stranger filling the
        # owner's inbox can't stop the owner's own laptop from getting codes.
        def mail_count(email_address, device_digest)
          scope = where(email_address: email_address, created_at: 1.hour.ago..)
          scope = scope.where(device_token_digest: device_digest) if device_digest
          scope.count
        end

        def recent_login_code(email_address)
          live.where(email_address: email_address)
            .where(failed_attempts: ...MAX_ATTEMPTS)
            .where(created_at: RESEND_INTERVAL.ago..).order(:created_at).last
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
          just_locked = just_locked?(login_code.email_address, device_digest: login_code.lockout_scope)
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
