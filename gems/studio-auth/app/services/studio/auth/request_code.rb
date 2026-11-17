module Studio
  module Auth
    # Mails a sign-in code for an email address, or says why not. Returns an
    # Issued, or :undeliverable, :no_account, :resend_too_soon or
    # :too_many_requests.
    module RequestCode
      Issued = Data.define(:id, :code)

      class << self
        def call(email_address:, device_cookie:, ip_address:, user_agent:, account_required: false, resend: false)
          email_address = TypedInput.email_address(email_address)
          return :undeliverable if Deliverability.undeliverable?(email_address)
          return :too_many_requests if SignInLimits.ip_over_hourly_limit?(ip_address)

          user = ::User.find_by(email_address: email_address)
          if account_required && user.nil? && !PendingSignUp.live.exists?(email_address: email_address)
            return :no_account
          end

          device_cookie.ensure_device_token!
          known_device = device_cookie.trusted_for?(user)
          device_digest = KnownDevice.digest(device_cookie.device_token) if known_device
          app_review = AppReviewAccounts.include?(email_address)

          LoginCode.transaction do
            LoginCode.lock_address(email_address)
            # The same browser asking again (a double submit, or a retry after
            # a lost response) gets its own code back, unless it asked for a
            # new one. Another browser inside the resend window must not: it
            # could burn the first browser's attempts. A known device takes
            # over instead.
            recent = SignInLimits.code_in_resend_window(email_address)
            if recent&.from?(device_cookie)
              next Issued.new(id: recent.id, code: nil) if !resend
              next :resend_too_soon if SignInLimits.resend_too_soon?(recent)
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

        private

        def issue(email_address:, known_device:, device_cookie:, ip_address:, user_agent:)
          code = AppReviewAccounts.code_for(email_address) || Secrets.generate_code
          LoginCode.live.where(email_address: email_address).update_all(expires_at: Time.current)
          login_code = LoginCode.create!(
            email_address: email_address,
            code_digest: LoginCode.digest_code(code),
            expires_at: LoginCode::TTL.from_now, known_device: known_device,
            device_token_digest: KnownDevice.digest(device_cookie.device_token),
            ip_address: ip_address, user_agent: user_agent
          )

          SignInMailer.with(login_code: login_code, encrypted_code: Secrets.encrypt(code), locale: I18n.locale.to_s)
            .login_code.deliver_later
          Rails.event.notify("authentication.login_code_issued")
          Issued.new(id: login_code.id, code: code)
        end
      end
    end
  end
end
