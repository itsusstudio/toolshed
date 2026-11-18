module Studio
  module Auth
    module RequestCode
      Issued = Data.define(:id, :code)

      class << self
        def call(email_address:, device_cookie:, ip_address:, user_agent:, account_required: false, resend: false,
          purpose: :sign_in, user: nil)
          email_address = TypedInput.email_address(email_address)
          return :undeliverable if Deliverability.undeliverable?(email_address)
          return :too_many_requests if SignInLimits.ip_over_hourly_limit?(ip_address)

          owner = ::User.find_by(email_address: email_address)
          if account_required && owner.nil? && !PendingSignUp.live.exists?(email_address: email_address)
            return :no_account
          end

          device_cookie.ensure_device_token!
          known_device = device_cookie.trusted_for?(owner)
          device_digest = KnownDevice.digest(device_cookie.device_token) if known_device
          app_review = AppReviewAccounts.include?(email_address)

          LoginCode.transaction do
            LoginCode.lock_address(email_address)
            recent = SignInLimits.code_in_resend_window(email_address)
            if recent&.from?(device_cookie)
              next Issued.new(id: recent.id, code: nil) if !resend
            elsif recent && !known_device && !app_review
              next :too_many_requests
            end
            next :too_many_codes if SignInLimits.locked_out?(email_address, device_digest: device_digest)
            if SignInLimits.mail_budget_spent?(email_address, device_digest: device_digest) && !app_review
              next :too_many_codes
            end

            issue(email_address: email_address, known_device: known_device, device_cookie: device_cookie,
              ip_address: ip_address, user_agent: user_agent, purpose: purpose, user: user)
          end
        end

        private

        def issue(email_address:, known_device:, device_cookie:, ip_address:, user_agent:, purpose: :sign_in, user: nil)
          code = AppReviewAccounts.code_for(email_address) || Secrets.generate_code
          LoginCode.live.where(email_address: email_address).update_all(expires_at: Time.current)
          login_code = LoginCode.create!(
            email_address: email_address,
            code_digest: LoginCode.digest_code(code),
            expires_at: LoginCode::TTL.from_now, known_device: known_device,
            device_token_digest: KnownDevice.digest(device_cookie.device_token),
            ip_address: ip_address, user_agent: user_agent
          )

          mail_params = {login_code: login_code, encrypted_code: Secrets.encrypt(code), locale: I18n.locale.to_s,
                         purpose: purpose.to_s}
          mail_params[:user] = user if user
          SignInMailer.with(**mail_params).login_code.deliver_later
          Rails.event.notify("authentication.login_code_issued")
          Issued.new(id: login_code.id, code: code)
        end
      end
    end
  end
end
