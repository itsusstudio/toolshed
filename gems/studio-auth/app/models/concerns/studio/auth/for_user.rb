module Studio
  module Auth
    module ForUser
      extend ActiveSupport::Concern

      STAFF_EMAIL_DOMAIN = "itsusstudio.com"

      included do
        has_many :sessions, class_name: "::Session", dependent: :delete_all
        has_many :login_codes, class_name: "Studio::Auth::LoginCode", primary_key: :email_address,
          foreign_key: :email_address, inverse_of: false, dependent: :delete_all
        has_many :known_devices, class_name: "Studio::Auth::KnownDevice", dependent: :delete_all
        has_many :invitations, class_name: "Studio::Auth::Invitation", dependent: :delete_all
        has_one :open_invitation, -> { open }, class_name: "Studio::Auth::Invitation", inverse_of: :user

        normalizes :email_address, with: ->(email_address) { TypedInput.email_address(email_address).presence }

        validates :email_address, presence: true, if: :requires_email_address?
        validates :email_address, uniqueness: true, length: {maximum: 254},
          format: {with: URI::MailTo::EMAIL_REGEXP}, allow_nil: true
        validate :email_address_deliverable, if: -> { email_address.present? && will_save_change_to_email_address? }

        validate :staff_email_domain, if: -> { self[:staff] }

        scope :staff, -> {
          where(staff: true).where(arel_table[:email_address].matches("%@#{STAFF_EMAIL_DOMAIN}"))
            .where.not(email_address: AppReviewAccounts.all.keys)
        }
      end

      def staff?
        super && email_address.to_s.end_with?("@#{STAFF_EMAIL_DOMAIN}") && !app_review_account?
      end

      def can_sign_in?
        email_address.present?
      end

      def requires_email_address?
        true
      end

      def can_be_invited?
        email_address.blank?
      end

      def sign_in_locked?
        SignInLimits.locked_out?(email_address)
      end

      def unlock_sign_in!
        login_codes.delete_all
        Rails.event.notify("authentication.sign_in_unlocked", actor_id: id)
      end

      def app_review_account?
        AppReviewAccounts.include?(email_address)
      end

      private

      def staff_email_domain
        if !email_address.to_s.end_with?("@#{STAFF_EMAIL_DOMAIN}")
          errors.add(:staff, :studio_email_only, domain: STAFF_EMAIL_DOMAIN)
        elsif app_review_account?
          errors.add(:staff, :app_review_account)
        end
      end

      def email_address_deliverable
        return if !can_sign_in? || errors.include?(:email_address)
        deliverable = !Deliverability.undeliverable?(email_address) &&
          !Deliverability.domain_cannot_receive_mail?(email_address)
        errors.add(:email_address, :undeliverable) if !deliverable
      end
    end
  end
end
