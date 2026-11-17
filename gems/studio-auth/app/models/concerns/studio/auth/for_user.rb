module Studio
  module Auth
    module ForUser
      extend ActiveSupport::Concern

      # Staff sign in with codes mailed to studio Workspace inboxes, which have
      # enforced 2FA and are suspended when someone leaves.
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

      # Checked on every staff request, so a flag set from the console or by a
      # bug on any other address opens nothing. App review accounts are
      # refused too: their fixed code is shared with the store reviewers.
      def staff?
        super && email_address.to_s.end_with?("@#{STAFF_EMAIL_DOMAIN}") && !app_review_account?
      end

      def can_sign_in?
        email_address.present?
      end

      # A user who never signs in, like a team member without a login, may
      # have no email address. Apps override this to say which users those are.
      def requires_email_address?
        true
      end

      # Only users without a login can be invited; apps can narrow it further,
      # e.g. not while archived.
      def can_be_invited?
        email_address.blank?
      end

      def sign_in_locked?
        SignInLimits.locked_out?(email_address)
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
        if !email_address.to_s.end_with?("@#{STAFF_EMAIL_DOMAIN}")
          errors.add(:staff, :studio_email_only, domain: STAFF_EMAIL_DOMAIN)
        elsif app_review_account?
          errors.add(:staff, :app_review_account)
        end
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
