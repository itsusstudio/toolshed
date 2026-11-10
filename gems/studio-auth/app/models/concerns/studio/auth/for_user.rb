module Studio
  module Auth
    module ForUser
      extend ActiveSupport::Concern

      included do
        has_many :sessions, class_name: "::Session", dependent: :delete_all
        has_many :login_codes, class_name: "Studio::Auth::LoginCode", dependent: :delete_all
        has_many :known_devices, class_name: "Studio::Auth::KnownDevice", dependent: :delete_all

        normalizes :email_address, with: ->(email_address) { TypedInput.email_address(email_address) }

        validates :email_address, presence: true, uniqueness: true, length: {maximum: 254},
          format: {with: URI::MailTo::EMAIL_REGEXP}
      end

      def can_sign_in?
        true
      end

      def sign_in_locked?
        LoginCode.locked_out?(self)
      end

      # For support: lifts a lockout at once. Clearing the login codes resets
      # the wrong-code count and the hourly mail budget, and cancels any code
      # still waiting to be typed. Sessions and known devices stay.
      def unlock_sign_in!
        login_codes.delete_all
        Events.notify("sign_in_unlocked", actor_id: id)
      end

      def app_review_account?
        AppReviewAccounts.include?(email_address)
      end
    end
  end
end
