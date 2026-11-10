module Studio
  module Auth
    # Not ApplicationMailer: the app's mailer layout and hooks must not touch
    # auth mail. An app restyles it at layouts/studio/auth/sign_in_mailer.
    class SignInMailer < ActionMailer::Base # standard:disable Rails/ApplicationMailer
      self.delivery_job = MailDeliveryJob

      default from: -> { Auth.config.mail_from }

      helper_method :app_name, :support_email

      # Returns without mailing for decoys, app review accounts and codes
      # that expired in the queue; Action Mailer then delivers nothing.
      def login_code
        login_code = params[:login_code]
        @user = login_code.user
        return if @user.nil?

        @code = Secrets.decrypt(params[:encrypted_code])
        return Rails.event.notify("authentication.login_code_expired_in_queue", actor_id: @user.id) if @code.nil?

        deliver_to(@user, :login_code, code: @code)
      end

      def locked
        @user = params[:user]
        deliver_to(@user, :locked)
      end

      private

      def deliver_to(user, action, **subject_values)
        return if user.app_review_account?

        I18n.with_locale(locale_for(user)) do
          # Marks the mail as machine-sent, so out-of-office replies and
          # auto-forward rules leave it alone (RFC 3834).
          headers["Auto-Submitted"] = "auto-generated"
          subject = t("studio_auth.sign_in_mailer.#{action}.subject", app_name: app_name, **subject_values)
          mail(to: user.email_address, subject: subject) do |format|
            format.text
            format.html
          end
        end
      end

      def locale_for(user)
        locale = user.try(:locale).presence
        (locale && I18n.available_locales.map(&:to_s).include?(locale.to_s)) ? locale : I18n.locale
      end

      def app_name
        Auth.config.app_name
      end

      def support_email
        Auth.config.support_email
      end
    end
  end
end
