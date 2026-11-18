module Studio
  module Auth
    class SignInMailer < ActionMailer::Base # standard:disable Rails/ApplicationMailer
      self.delivery_job = MailDeliveryJob

      default from: -> { Auth.config.mail_from }

      helper_method :app_name

      def login_code
        login_code = params[:login_code]
        purpose = params[:purpose].to_s
        @user = params.fetch(:user) { ::User.find_by(email_address: login_code.email_address) }
        return if @user && !@user.can_sign_in?

        @code = Secrets.decrypt(params[:encrypted_code])
        return Rails.event.notify("authentication.login_code_expired_in_queue", actor_id: @user&.id) if @code.nil?

        case purpose
        when "email_address_change"
          deliver_to(@user, :email_address_change_code, code: @code)
        when "new_email_address"
          return if @user.app_review_account?

          deliver(login_code.email_address, :new_email_address_code, locale: @user.try(:locale), code: @code)
        else
          return deliver_to(@user, :login_code, code: @code) if @user

          deliver(login_code.email_address, :sign_up_code, locale: params[:locale], code: @code)
        end
      end

      def email_address_changed
        @user = params[:user]
        @new_email_address = @user.email_address
        @device = SessionDevice.from_user_agent(params[:user_agent]).name
        @changed_at = params[:changed_at]
        @support_email_address = Auth.config.support_email_address
        headers["Reply-To"] = @support_email_address if @support_email_address
        deliver(params[:old_email_address], :email_address_changed, locale: @user.try(:locale))
      end

      def locked
        @user = params[:user]
        deliver_to(@user, :locked)
      end

      def invite
        @invitation = params[:invitation]
        return if @invitation.accepted_at || @invitation.revoked_at

        token = Secrets.decrypt(params[:encrypted_token])
        return if token.nil?

        @url = main_app.invitation_url(token: token)
        @details = @invitation.user.try(:invitation_details) || {}
        @inviter = @invitation.invited_by
        @inviter_name = @inviter.try(:full_name).presence || @inviter.email_address
        deliver(@invitation.email_address, :invite, locale: @invitation.user.try(:locale),
          inviter: @inviter_name, place: @details.fetch(:place, app_name))
      end

      private

      def deliver_to(user, action, **subject_values)
        return if user.app_review_account?

        deliver(user.email_address, action, locale: user.try(:locale), **subject_values)
      end

      def deliver(email_address, action, locale:, template: action.to_s, **subject_values)
        I18n.with_locale(available_locale(locale)) do
          headers["Auto-Submitted"] = "auto-generated"
          subject = t("studio_auth.sign_in_mailer.#{action}.subject", app_name: app_name, **subject_values)
          mail(to: email_address, subject: subject, template_name: template) do |format|
            format.text
            format.html
          end
        end
      end

      def available_locale(locale)
        (locale.present? && I18n.available_locales.map(&:to_s).include?(locale.to_s)) ? locale : I18n.locale
      end

      def app_name
        Auth.config.app_name
      end
    end
  end
end
