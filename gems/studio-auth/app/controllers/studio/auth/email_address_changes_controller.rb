module Studio
  module Auth
    class EmailAddressChangesController < BaseController
      layout "studio/task"

      rate_limit to: 10, within: 1.minute, only: :create, name: "ip",
        by: -> { rate_limit_key }, with: :too_many_requests

      def new
        @form = EmailAddressChangeForm.new(user: current_user,
          email_address: EmailAddressChange.from_rails_session(session, user: current_user)&.new_email_address)
        @field_error = flash[:studio_auth_field_error]
      end

      def create
        @form = build_form
        return render(:new, status: :unprocessable_content) if @form.invalid?

        new_email_address = @form.normalized_email_address
        step = recently_authenticated? ? :new : :current
        issued = request_code_for(step, new_email_address)
        return show_request_error(issued) if issued.is_a?(Symbol)

        EmailAddressChange.store_in_rails_session(session, user: current_user, new_email_address: new_email_address,
          step: step, issued: issued)
        redirect_to main_app.verify_email_address_change_path, status: :see_other
      end

      private

      def build_form
        EmailAddressChangeForm.new(user: current_user, email_address: params[:email_address])
      end

      def request_code_for(step, new_email_address)
        RequestCode.call(
          email_address: (step == :current) ? current_user.email_address : new_email_address,
          purpose: (step == :current) ? :email_address_change : :new_email_address,
          user: current_user, **code_request_details
        )
      end

      def show_request_error(error)
        @field_error = t("studio_auth.errors.email_address.#{error}")
        render :new, status: (error == :undeliverable) ? :unprocessable_content : :too_many_requests
      end
    end
  end
end
