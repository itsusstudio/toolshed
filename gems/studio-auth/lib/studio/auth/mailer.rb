module Studio
  module Auth
    class Mailer < ActionMailer::Base # standard:disable Rails/ApplicationMailer -- the app's mailer layout and hooks must not touch auth mail; an app restyles it at layouts/studio/auth/mailer
      self.delivery_job = MailDeliveryJob

      default from: -> { Auth.config.mail_from }

      helper_method :app_name, :support_email

      # Returns without mailing for decoys, review accounts and codes that
      # expired in the queue; Action Mailer then delivers nothing.
      def login_code
        challenge = params[:challenge]
        @user = challenge.user
        return if @user.nil? || @user.review_account?

        @code = Secrets.decrypt(params[:encrypted_code])
        return Events.notify("login_code_expired_in_queue", actor_id: @user.id) if @code.nil?

        @purpose = challenge.purpose
        @device = DeviceDescription.call(challenge.user_agent)
        @ip_address = challenge.ip_address
        deliver_to(@user, :login_code, code: @code)
      end

      def new_device
        @user = params[:user]
        return if @user.review_account?

        @device = DeviceDescription.call(params[:user_agent])
        @ip_address = params[:ip_address]
        @signed_in_at = params[:signed_in_at]
        deliver_to(@user, :new_device)
      end

      def locked
        @user = params[:user]
        return if @user.review_account?

        deliver_to(@user, :locked)
      end

      private

      def deliver_to(user, action, **subject_values)
        I18n.with_locale(locale_for(user)) do
          mail(to: user.email_address, subject: t("studio_auth.mailer.#{action}.subject", app_name: app_name, **subject_values)) do |format|
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
