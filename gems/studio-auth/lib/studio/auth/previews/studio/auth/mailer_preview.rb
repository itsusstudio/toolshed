module Studio
  module Auth
    class MailerPreview < ActionMailer::Preview
      USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15"

      def login_code
        Mailer.with(login_code: sample_login_code, encrypted_code: Secrets.encrypt("381904")).login_code
      end

      def new_device
        Mailer.with(user: user, user_agent: USER_AGENT, signed_in_at: Time.current).new_device
      end

      def locked
        Mailer.with(user: user).locked
      end

      private

      def user
        ::User.new(email_address: "preview@example.com")
      end

      def sample_login_code
        LoginCode.new(user: user, user_agent: USER_AGENT, ip_address: "203.0.113.7")
      end
    end
  end
end
