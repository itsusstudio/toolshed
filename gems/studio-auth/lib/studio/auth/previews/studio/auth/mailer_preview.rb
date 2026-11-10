module Studio
  module Auth
    class MailerPreview < ActionMailer::Preview
      USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15"

      def login_code
        Mailer.with(challenge: challenge("sign_in"), encrypted_code: Secrets.encrypt("381904")).login_code
      end

      def reauthentication_code
        Mailer.with(challenge: challenge("reauthentication"), encrypted_code: Secrets.encrypt("381904")).login_code
      end

      def new_device
        Mailer.with(user: user, user_agent: USER_AGENT, ip_address: "203.0.113.7", signed_in_at: Time.current).new_device
      end

      def locked
        Mailer.with(user: user).locked
      end

      private

      # Unsaved, so previews never write to the database.
      def user
        ::User.new(email_address: "preview@example.com")
      end

      def challenge(purpose)
        LoginChallenge.new(user: user, purpose: purpose, user_agent: USER_AGENT, ip_address: "203.0.113.7")
      end
    end
  end
end
