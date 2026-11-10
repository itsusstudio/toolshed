module Studio
  module Auth
    module Challenges
      Issued = Data.define(:id, :code)
      Verified = Data.define(:status, :user)

      MAIL_BUDGET = 10

      # Stands in for a missing user in queries. Decoys then run the same
      # queries as a real address, so response time doesn't reveal which
      # addresses have accounts.
      NO_USER_ID = 0

      class << self
        # Anything that would treat this browser differently from an unknown
        # address answers with a decoy instead, so responses never reveal
        # whether an account exists or what state it is in.
        def request_sign_in(email_address:, device:, ip_address:, user_agent:)
          email_address = Auth.normalize_email(email_address)
          return :undeliverable if Deliverability.undeliverable?(email_address)
          # Backs up the cache-held rate limits, which turn off if the cache
          # fails; this one counts in the primary database and fails closed.
          return :too_many_requests if ip_over_hourly_limit?(ip_address)

          device.ensure_token!
          found = ::User.find_by(email_address: email_address)
          known_device = device.known_for?(found)
          attributes = {purpose: "sign_in", known_device: known_device, device: device, ip_address: ip_address, user_agent: user_agent}

          LoginChallenge.transaction do
            user = ::User.lock.find_by(id: found&.id || NO_USER_ID)
            reason = decoy_reason(user, device: device, known_device: known_device)

            # The same browser asking again (a double submit, or a retry after
            # a lost response) gets its own challenge back. Another browser
            # inside the resend window must not: it could burn the first
            # browser's attempts or read its attempt count. A known device
            # takes over instead.
            recent = recent_challenge(user, "sign_in")
            next issue_decoy(reason: reason, user: user, **attributes) if reason
            next Issued.new(id: recent.id, code: nil) if recent&.from?(device)
            next issue_decoy(reason: "resend_window", user: user, **attributes) if recent && !known_device && !user.review_account?

            issue(user: user, **attributes)
          end
        end

        # The device check matters here too: a stolen session cookie on a new
        # device must hit the lockout, or reauthentication becomes an
        # unlimited way to guess into sudo-protected actions.
        def request_reauthentication(user:, device:, ip_address:, user_agent:)
          device.ensure_token!
          known_device = device.known_for?(user)
          LoginChallenge.transaction do
            ::User.lock.find(user.id)
            recent = recent_challenge(user, "reauthentication")
            next Issued.new(id: recent.id, code: nil) if recent&.from?(device)

            issue(user: user, purpose: "reauthentication", known_device: known_device, device: device, ip_address: ip_address, user_agent: user_agent)
          end
        end

        def verify(id:, code:, purpose:, user: nil)
          found = LoginChallenge.find_by(id: id, purpose: purpose)
          return Verified.new(status: :expired, user: nil) if found.nil?

          LoginChallenge.transaction do
            owner = ::User.lock.find_by(id: found.user_id || NO_USER_ID)
            challenge = LoginChallenge.lock.find(found.id)
            challenge.user = owner if owner
            next Verified.new(status: :expired, user: nil) if challenge.finished?
            next Verified.new(status: :expired, user: nil) if user && challenge.user_id != user.id
            next Verified.new(status: :too_many_attempts, user: nil) if challenge.exhausted?

            # Both checks run for decoys too, so a decoy costs the same time.
            blocked = blocked?(challenge)
            matches = challenge.code_matches?(code.to_s)
            if matches && !blocked
              challenge.update!(consumed_at: Time.current)
              Events.notify("login_challenge_verified", purpose: purpose, actor_id: challenge.user_id)
              next Verified.new(status: :verified, user: owner)
            end

            record_failure(challenge)
            Verified.new(status: challenge.exhausted? ? :too_many_attempts : :invalid, user: nil)
          end
        end

        private

        def ip_over_hourly_limit?(ip_address)
          LoginChallenge.where(ip_address: ip_address, created_at: 1.hour.ago..).count >= SIGN_IN_IP_HOURLY_LIMIT
        end

        # Every query runs whatever the answer, so a decoy takes as long as a
        # real address.
        def decoy_reason(user, device:, known_device:)
          device_digest = KnownDevice.digest_token(device.token) if known_device
          locked = Lockout.locked?(user, device_digest: device_digest)
          over_budget = mail_count(user, device_digest) >= MAIL_BUDGET

          return "unknown_address" if user.nil?
          return "cannot_sign_in" if !user.can_sign_in?
          return "locked" if locked

          "mail_budget" if over_budget && !user.review_account?
        end

        # A known device has its own budget, so a stranger filling the
        # owner's inbox can't stop the owner's own laptop from getting codes.
        def mail_count(user, device_digest)
          scope = LoginChallenge.where(user_id: user&.id || NO_USER_ID, purpose: "sign_in", created_at: 1.hour.ago..)
          scope = scope.where(device_token_digest: device_digest) if device_digest
          scope.count
        end

        def recent_challenge(user, purpose)
          LoginChallenge.live.where(user_id: user&.id || NO_USER_ID, purpose: purpose, failed_attempts: ...CODE_MAX_ATTEMPTS)
            .where(created_at: CODE_RESEND_INTERVAL.ago..).order(:created_at).last
        end

        def issue_decoy(reason:, user:, **attributes)
          Events.notify("sign_in_decoyed", reason: reason, actor_id: user&.id)
          issue(user: nil, **attributes)
        end

        def issue(user:, purpose:, known_device:, device:, ip_address:, user_agent:)
          code = (ReviewAccounts.code_for(user.email_address) if user) || Secrets.generate_code
          LoginChallenge.live.where(user_id: user&.id || NO_USER_ID, purpose: purpose).update_all(expires_at: Time.current)
          challenge = LoginChallenge.create!(
            user: user, purpose: purpose,
            code_digest: LoginChallenge.digest_code(code),
            expires_at: CODE_TTL.from_now, known_device: known_device,
            device_token_digest: KnownDevice.digest_token(device.token),
            ip_address: ip_address, user_agent: user_agent
          )

          # Decoys enqueue too, so a real address takes the same time to answer.
          Mailer.with(challenge: challenge, encrypted_code: Secrets.encrypt(code)).login_code.deliver_later
          Events.notify("login_challenge_issued", purpose: purpose, actor_id: user&.id, decoy: user.nil?)
          Issued.new(id: challenge.id, code: code)
        end

        def blocked?(challenge)
          locked = Lockout.locked?(challenge.user, device_digest: lockout_scope(challenge))
          !challenge.decoy? && (locked || !challenge.user.can_sign_in?)
        end

        def lockout_scope(challenge)
          challenge.device_token_digest if challenge.known_device
        end

        def record_failure(challenge)
          challenge.update!(failed_attempts: challenge.failed_attempts + 1, failed_at: Time.current)
          just_locked = Lockout.just_locked?(challenge.user, device_digest: lockout_scope(challenge))
          Events.notify("login_challenge_rejected", purpose: challenge.purpose, actor_id: challenge.user_id)
          return if challenge.decoy?

          review_account = challenge.user.review_account?
          Events.notify("review_account_code_rejected", actor_id: challenge.user_id) if review_account
          return if !just_locked

          Events.notify(review_account ? "review_account_locked" : "account_locked", actor_id: challenge.user_id)
          Mailer.with(user: challenge.user).locked.deliver_later if !review_account
        end
      end
    end
  end
end
