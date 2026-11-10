module Studio
  module Auth
    module User
      extend ActiveSupport::Concern

      included do
        has_many :sessions, class_name: "::Session", dependent: :delete_all
        has_many :login_challenges, class_name: "Studio::Auth::LoginChallenge", dependent: :delete_all
        has_many :known_devices, class_name: "Studio::Auth::KnownDevice", dependent: :delete_all

        normalizes :email_address, with: ->(email_address) { Auth.normalize_email(email_address) }

        validates :email_address, presence: true, uniqueness: true, length: {maximum: 254},
          format: {with: URI::MailTo::EMAIL_REGEXP}
      end

      # Apps return false for accounts that must not sign in (deleted,
      # suspended); they then get decoys and their sessions stop working.
      def can_sign_in?
        true
      end

      def review_account?
        ReviewAccounts.include?(email_address)
      end
    end
  end
end
