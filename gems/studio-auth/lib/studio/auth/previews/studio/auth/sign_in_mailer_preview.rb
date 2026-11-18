module Studio
  module Auth
    class SignInMailerPreview < ActionMailer::Preview
      USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15"

      def login_code
        SignInMailer.with(login_code: sample_login_code, user: user, encrypted_code: Secrets.encrypt("381904")).login_code
      end

      def sign_up_code
        SignInMailer.with(login_code: sample_login_code, user: nil, encrypted_code: Secrets.encrypt("381904")).login_code
      end

      def invite
        invitation = Invitation.new(user: user, invited_by: ::User.new(email_address: "dana@example.com"),
          email_address: "sam@example.com", expires_at: Invitation::TTL.from_now)
        SignInMailer.with(invitation: invitation, encrypted_token: Secrets.encrypt("x7Kq2mP9")).invite
      end

      def email_address_change_code
        SignInMailer.with(login_code: sample_login_code, user: user, purpose: "email_address_change",
          encrypted_code: Secrets.encrypt("381904")).login_code
      end

      def new_email_address_code
        SignInMailer.with(login_code: LoginCode.new(email_address: "new@example.com"), user: user,
          purpose: "new_email_address", encrypted_code: Secrets.encrypt("381904")).login_code
      end

      def email_address_changed
        SignInMailer.with(user: ::User.new(email_address: "new@example.com"), old_email_address: "preview@example.com",
          user_agent: USER_AGENT, changed_at: Time.current).email_address_changed
      end

      def locked
        SignInMailer.with(user: user).locked
      end

      private

      def user
        ::User.new(email_address: "preview@example.com")
      end

      def sample_login_code
        LoginCode.new(email_address: "preview@example.com", user_agent: USER_AGENT, ip_address: "203.0.113.7")
      end
    end
  end
end
