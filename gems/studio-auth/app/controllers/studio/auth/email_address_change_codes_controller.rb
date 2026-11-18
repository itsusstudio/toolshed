module Studio
  module Auth
    class EmailAddressChangeCodesController < BaseController
      layout "studio/task"

      before_action :require_email_address_change

      rate_limit to: 20, within: 1.minute, only: [:create, :resend], name: "ip",
        by: -> { rate_limit_key }, with: :too_many_requests

      def new
        @field_error = flash[:studio_auth_field_error]
      end

      def create
        result = VerifyCode.call(id: @change.code_id, code: submitted_code)
        return show_code_error(result.status) if result.status != :verified
        return verify_current_address(result) if @change.step == :current

        verify_new_address(result)
      end

      def resend
        issued = request_code(@change.step, resend: true)
        if issued.is_a?(Symbol)
          flash[:studio_auth_field_error] = t("studio_auth.errors.email_address.#{issued}")
          return redirect_to(main_app.verify_email_address_change_path, status: :see_other)
        end

        store_change(@change.step, issued)
        redirect_to main_app.verify_email_address_change_path, status: :see_other
      end

      private

      def require_email_address_change
        @change = EmailAddressChange.from_rails_session(session, user: current_user)
        redirect_to main_app.change_email_address_path, status: :see_other if @change.nil?
      end

      def verify_current_address(result)
        return show_code_error(:expired) if result.user != current_user

        mark_recently_authenticated
        issued = request_code(:new)
        return back_to_change_form(issued) if issued.is_a?(Symbol)

        store_change(:new, issued)
        redirect_to main_app.verify_email_address_change_path, status: :see_other
      end

      def verify_new_address(result)
        EmailAddressChange.delete_from_rails_session(session)
        change = ChangeEmailAddress.call(user: current_user, email_address: result.email_address,
          user_agent: request.user_agent)
        return back_to_change_form(change.errors.first.type) if change.errors.any?

        redirect_to account_settings_path, status: :see_other,
          notice: t("studio_auth.flash.email_address_changed", email_address: current_user.email_address)
      end

      def back_to_change_form(error)
        EmailAddressChange.delete_from_rails_session(session)
        flash[:studio_auth_field_error] = t("studio_auth.errors.email_address.#{error}", domain: ForUser::STAFF_EMAIL_DOMAIN)
        redirect_to main_app.change_email_address_path, status: :see_other
      end

      def request_code(step, resend: false)
        RequestCode.call(
          email_address: (step == :current) ? current_user.email_address : @change.new_email_address,
          purpose: (step == :current) ? :email_address_change : :new_email_address,
          user: current_user, resend: resend, **code_request_details
        )
      end

      def store_change(step, issued)
        EmailAddressChange.store_in_rails_session(session, user: current_user,
          new_email_address: @change.new_email_address, step: step, issued: issued)
      end

      def show_code_error(status)
        @field_error = t("studio_auth.errors.code.#{status}")
        render :new, status: :unprocessable_content
      end
    end
  end
end
