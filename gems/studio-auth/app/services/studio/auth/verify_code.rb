module Studio
  module Auth
    module VerifyCode
      Result = Data.define(:status, :email_address, :user) do
        def initialize(status:, email_address: nil, user: nil) = super
      end

      class << self
        def call(id:, code:)
          found = LoginCode.find_by(id: id)
          return Result.new(status: :expired) if found.nil?

          LoginCode.transaction do
            LoginCode.lock_address(found.email_address)
            login_code = LoginCode.lock.find(found.id)
            next Result.new(status: :expired) if login_code.finished? || login_code.email_address.blank?
            next Result.new(status: :too_many_attempts) if login_code.exhausted?

            user = ::User.find_by(email_address: login_code.email_address)
            blocked = SignInLimits.locked_out?(login_code.email_address, device_digest: login_code.lockout_scope) ||
              (user && !user.can_sign_in?)
            if login_code.code_matches?(code.to_s) && !blocked
              login_code.update!(consumed_at: Time.current)
              Rails.event.notify("authentication.login_code_verified", actor_id: user&.id)
              next Result.new(status: :verified, email_address: login_code.email_address, user: user)
            end

            record_failure(login_code, user)
            Result.new(status: login_code.exhausted? ? :too_many_attempts : :invalid)
          end
        end

        private

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
    end
  end
end
