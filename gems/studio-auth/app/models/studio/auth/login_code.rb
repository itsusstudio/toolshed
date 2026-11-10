module Studio
  module Auth
    class LoginCode < ActiveRecord::Base # standard:disable Rails/ApplicationRecord -- a gem has no ApplicationRecord
      Issued = Data.define(:id, :code)
      Verification = Data.define(:status, :user)

      TTL = 10.minutes
      MAX_ATTEMPTS = 5
      RESEND_INTERVAL = 60.seconds
      MAIL_BUDGET = 10
      IP_HOURLY_LIMIT = 30

      LOCKOUT_WINDOW = 24.hours
      LOCKOUT_WRONG_CODES = 10
      LOCKOUT_DURATION = 1.hour
      APP_REVIEW_LOCKOUT_WRONG_CODES = 20

      # Decoys have no user, but must run the same queries as a real address
      # so response time doesn't reveal which addresses have accounts. No
      # user has id 0; a nil id would query IS NULL and scan every decoy.
      DECOY_USER_ID = 0

      belongs_to :user, class_name: "::User", optional: true

      validates :code_digest, :expires_at, presence: true

      scope :live, -> { where(consumed_at: nil).where(arel_table[:expires_at].gt(Time.current)) }
      scope :within_lockout_window, -> { where(created_at: LOCKOUT_WINDOW.ago..) }
      scope :purgeable, -> { where(created_at: ...LOCKOUT_WINDOW.ago) }

      class << self
        # Anything that would treat this browser differently from an unknown
        # address answers with a decoy instead, so responses never reveal
        # whether an account exists or what state it is in.
        def request_for(email_address:, device_cookie:, ip_address:, user_agent:)
          email_address = TypedInput.email_address(email_address)
          return :undeliverable if Deliverability.undeliverable?(email_address)
          # Backs up the cache-held rate limits, which turn off if the cache
          # fails; this one counts in the primary database and fails closed.
          return :too_many_requests if ip_over_hourly_limit?(ip_address)

          device_cookie.ensure_device_token!
          found = ::User.find_by(email_address: email_address)
          known_device = device_cookie.trusted_for?(found)
          attributes = {
            known_device: known_device, device_cookie: device_cookie,
            ip_address: ip_address, user_agent: user_agent
          }

          transaction do
            user = ::User.lock.find_by(id: found&.id || DECOY_USER_ID)
            reason = decoy_reason(user, device_cookie: device_cookie, known_device: known_device)

            # The same browser asking again (a double submit, or a retry after
            # a lost response) gets its own code back. Another browser
            # inside the resend window must not: it could burn the first
            # browser's attempts or read its attempt count. A known device
            # takes over instead.
            recent = recent_login_code(user)
            next issue_decoy(reason: reason, user: user, **attributes) if reason
            next Issued.new(id: recent.id, code: nil) if recent&.from?(device_cookie)
            takes_over = known_device || user.app_review_account?
            next issue_decoy(reason: "resend_window", user: user, **attributes) if recent && !takes_over

            issue(user: user, **attributes)
          end
        end

        def verify(id:, code:)
          found = find_by(id: id)
          return Verification.new(status: :expired, user: nil) if found.nil?

          transaction do
            owner = ::User.lock.find_by(id: found.user_id || DECOY_USER_ID)
            login_code = lock.find(found.id)
            login_code.user = owner if owner
            next Verification.new(status: :expired, user: nil) if login_code.finished?
            next Verification.new(status: :too_many_attempts, user: nil) if login_code.exhausted?

            blocked = blocked?(login_code)
            matches = login_code.code_matches?(code.to_s)
            if matches && !blocked
              login_code.update!(consumed_at: Time.current)
              Rails.event.notify("authentication.login_code_verified", actor_id: login_code.user_id)
              next Verification.new(status: :verified, user: owner)
            end

            record_failure(login_code)
            Verification.new(status: login_code.exhausted? ? :too_many_attempts : :invalid, user: nil)
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
        def locked_out?(user, device_digest: nil)
          failures, last_failed_at = failure_stats(user, device_digest)
          return false if user.nil? || last_failed_at.nil?
          return failures >= APP_REVIEW_LOCKOUT_WRONG_CODES if user.app_review_account?
          return false if failures < LOCKOUT_WRONG_CODES

          last_failed_at > (LOCKOUT_DURATION * (failures - LOCKOUT_WRONG_CODES + 1)).ago
        end

        def digest_code(code)
          Secrets.digest("login_code", code)
        end

        private

        # True only for the failure that first reaches the limit, so the
        # owner gets one lock email, not one per guess.
        def just_locked?(user, device_digest: nil)
          limit = user&.app_review_account? ? APP_REVIEW_LOCKOUT_WRONG_CODES : LOCKOUT_WRONG_CODES
          failure_stats(user, device_digest).first == limit
        end

        def failure_stats(user, device_digest)
          user_id = user&.id || DECOY_USER_ID
          recent = where(user_id: user_id).within_lockout_window
          recent = recent.where(device_token_digest: device_digest) if device_digest
          [recent.sum(:failed_attempts), recent.maximum(:failed_at)]
        end

        def ip_over_hourly_limit?(ip_address)
          where(ip_address: ip_address, created_at: 1.hour.ago..).count >= IP_HOURLY_LIMIT
        end

        # Every query runs whatever the answer, so a decoy takes as long as a
        # real address.
        def decoy_reason(user, device_cookie:, known_device:)
          device_digest = KnownDevice.digest(device_cookie.device_token) if known_device
          locked = locked_out?(user, device_digest: device_digest)
          over_budget = mail_count(user, device_digest) >= MAIL_BUDGET

          return "unknown_address" if user.nil?
          return "cannot_sign_in" if !user.can_sign_in?
          return "locked" if locked

          "mail_budget" if over_budget && !user.app_review_account?
        end

        # A known device has its own budget, so a stranger filling the
        # owner's inbox can't stop the owner's own laptop from getting codes.
        def mail_count(user, device_digest)
          scope = where(user_id: user&.id || DECOY_USER_ID, created_at: 1.hour.ago..)
          scope = scope.where(device_token_digest: device_digest) if device_digest
          scope.count
        end

        def recent_login_code(user)
          live.where(user_id: user&.id || DECOY_USER_ID)
            .where(failed_attempts: ...MAX_ATTEMPTS)
            .where(created_at: RESEND_INTERVAL.ago..).order(:created_at).last
        end

        def issue_decoy(reason:, user:, **attributes)
          Rails.event.notify("authentication.sign_in_decoyed", reason: reason, actor_id: user&.id)
          issue(user: nil, **attributes)
        end

        def issue(user:, known_device:, device_cookie:, ip_address:, user_agent:)
          code = (AppReviewAccounts.code_for(user.email_address) if user) || Secrets.generate_code
          live.where(user_id: user&.id || DECOY_USER_ID).update_all(expires_at: Time.current)
          login_code = create!(
            user: user,
            code_digest: digest_code(code),
            expires_at: TTL.from_now, known_device: known_device,
            device_token_digest: KnownDevice.digest(device_cookie.device_token),
            ip_address: ip_address, user_agent: user_agent
          )

          # Decoys enqueue too, so a real address takes the same time to answer.
          SignInMailer.with(login_code: login_code, encrypted_code: Secrets.encrypt(code)).login_code.deliver_later
          Rails.event.notify("authentication.login_code_issued", actor_id: user&.id, decoy: user.nil?)
          Issued.new(id: login_code.id, code: code)
        end

        def blocked?(login_code)
          locked = locked_out?(login_code.user, device_digest: lockout_scope(login_code))
          !login_code.decoy? && (locked || !login_code.user.can_sign_in?)
        end

        def lockout_scope(login_code)
          login_code.device_token_digest if login_code.known_device
        end

        def record_failure(login_code)
          login_code.update!(failed_attempts: login_code.failed_attempts + 1, failed_at: Time.current)
          just_locked = just_locked?(login_code.user, device_digest: lockout_scope(login_code))
          Rails.event.notify("authentication.login_code_rejected", actor_id: login_code.user_id)
          return if login_code.decoy?

          app_review_account = login_code.user.app_review_account?
          Rails.event.notify("authentication.app_review_account_code_rejected", actor_id: login_code.user_id) if app_review_account
          return if !just_locked

          event = app_review_account ? "app_review_account_locked" : "account_locked"
          Rails.event.notify("authentication.#{event}", actor_id: login_code.user_id)
          SignInMailer.with(user: login_code.user).locked.deliver_later if !app_review_account
        end
      end

      def decoy?
        user_id.nil?
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

      # The digest is compared for decoys too, so they cost the same time;
      # a decoy never matches.
      def code_matches?(code)
        matches = Secrets.matches?(code_digest, "login_code", code)
        matches && !decoy?
      end
    end
  end
end
