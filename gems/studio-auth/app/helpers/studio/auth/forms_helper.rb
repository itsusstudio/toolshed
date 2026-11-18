module Studio
  module Auth
    module FormsHelper
      def sign_up_prompt
        safe_join([t("studio_auth.sign_ins.new.no_account"),
          link_to(t("studio_auth.sign_ins.new.sign_up"), main_app.signup_path)], " ")
      end

      def sign_in_prompt
        safe_join([t("studio_auth.sign_ups.new.have_account"),
          link_to(t("studio_auth.sign_ups.new.sign_in"), main_app.login_path)], " ")
      end

      def field_error(form, attribute, **values)
        error = form&.errors&.where(attribute)&.first
        t("studio_auth.errors.#{attribute}.#{error.type}", **values) if error
      end

      def page_message
        if flash[:alert].present?
          tag.p(with_line_breaks(flash[:alert]), id: "studio-auth-alert", class: "u-error", role: "alert")
        elsif flash[:notice].present?
          tag.p(with_line_breaks(flash[:notice]), id: "studio-auth-notice", class: "u-text-small", role: "status")
        end
      end

      def with_line_breaks(text)
        tag.span(safe_join(text.to_s.split("\n"), tag.br)) if text.present?
      end
    end
  end
end
