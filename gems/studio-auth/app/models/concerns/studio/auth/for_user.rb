module Studio
  module Auth
    module ForUser
      extend ActiveSupport::Concern

      # Staff sign in with codes mailed to studio Workspace inboxes, which have
      # enforced 2FA and are suspended when someone leaves.
      STAFF_EMAIL_DOMAIN = "itsusstudio.com"

      included do
        has_many :sessions, class_name: "::Session", dependent: :delete_all
        has_many :login_codes, class_name: "Studio::Auth::LoginCode", dependent: :delete_all
        has_many :known_devices, class_name: "Studio::Auth::KnownDevice", dependent: :delete_all

        normalizes :email_address, with: ->(email_address) { TypedInput.email_address(email_address) }

        validates :email_address, presence: true, uniqueness: true, length: {maximum: 254},
          format: {with: URI::MailTo::EMAIL_REGEXP}
        validate :email_address_deliverable, if: :will_save_change_to_email_address?

        validate :staff_email_domain, if: -> { self[:staff] }

        scope :staff, -> { where(staff: true).where(arel_table[:email_address].matches("%@#{STAFF_EMAIL_DOMAIN}")) }
      end

      # Checked on every staff request, so a flag set from the console or by a
      # bug on any other address opens nothing.
      def staff?
        super && email_address.to_s.end_with?("@#{STAFF_EMAIL_DOMAIN}")
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
        Rails.event.notify("authentication.sign_in_unlocked", actor_id: id)
      end

      def app_review_account?
        AppReviewAccounts.include?(email_address)
      end

      private

      def staff_email_domain
        return if email_address.to_s.end_with?("@#{STAFF_EMAIL_DOMAIN}")

        errors.add(:staff, :studio_email_only, domain: STAFF_EMAIL_DOMAIN)
      end

      # Saving must refuse what sign-in would: start_sign_in_for has no answer
      # for an address the gem won't mail. Skipped for accounts that can't sign
      # in, whose address an app may park somewhere undeliverable.
      def email_address_deliverable
        return if !can_sign_in? || errors.include?(:email_address)
        deliverable = !Deliverability.undeliverable?(email_address) &&
          !Deliverability.domain_cannot_receive_mail?(email_address)
        errors.add(:email_address, :undeliverable) if !deliverable
      end
    end
  end
end
