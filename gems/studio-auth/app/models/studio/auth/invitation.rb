module Studio
  module Auth
    # Gives an existing user a login. The link carries a random token and only
    # its digest is stored; opening the link proves the inbox, so accepting
    # sets the user's address and signs them in.
    class Invitation < ActiveRecord::Base # standard:disable Rails/ApplicationRecord -- a gem has no ApplicationRecord
      TTL = 7.days

      belongs_to :user, class_name: "::User"
      belongs_to :invited_by, class_name: "::User"

      normalizes :email_address, with: ->(email_address) { TypedInput.email_address(email_address).presence }

      validates :email_address, presence: true, format: {with: URI::MailTo::EMAIL_REGEXP}
      validates :token_digest, :expires_at, presence: true
      validate :email_address_unused, on: :create

      scope :open, -> { where(accepted_at: nil, revoked_at: nil) }
      scope :pending, -> { open.where(arel_table[:expires_at].gt(Time.current)) }

      class << self
        # Replaces any open invitation for the user and mails the new one.
        def invite!(user:, email_address:, invited_by:)
          token = Secrets.generate_token
          invitation = transaction do
            open.where(user: user).update_all(revoked_at: Time.current)
            create!(user: user, invited_by: invited_by, email_address: email_address,
              token_digest: Secrets.digest("invitation", token), expires_at: TTL.from_now)
          end

          SignInMailer.with(invitation: invitation, encrypted_token: Secrets.encrypt(token)).invite.deliver_later
          Rails.event.notify("authentication.invitation_sent", actor_id: invited_by.id)
          invitation
        end

        def find_pending_by_token(token)
          pending.find_by(token_digest: Secrets.digest("invitation", token)) if token.present?
        end
      end

      def accept!
        transaction do
          user.update!(email_address: email_address)
          update!(accepted_at: Time.current)
        end
      end

      def revoke!
        update!(revoked_at: Time.current)
      end

      private

      def email_address_unused
        errors.add(:email_address, :taken) if ::User.where.not(id: user_id).exists?(email_address: email_address)
      end
    end
  end
end
