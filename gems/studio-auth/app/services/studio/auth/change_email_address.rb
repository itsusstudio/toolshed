module Studio
  module Auth
    module ChangeEmailAddress
      class << self
        def call(user:, email_address:, user_agent:)
          form = EmailAddressChangeForm.new(user: user, email_address: email_address)
          new_email_address = form.normalized_email_address
          old_email_address = user.email_address

          changed = LoginCode.transaction do
            LoginCode.lock_address(new_email_address)
            next false if form.invalid?
            next false if !update_email_address(user, new_email_address, form)

            LoginCode.live.where(email_address: old_email_address).update_all(expires_at: Time.current)
            PendingSignUp.where(email_address: new_email_address).delete_all
            true
          end
          return form if !changed

          Rails.event.notify("authentication.email_address_changed", actor_id: user.id)
          SignInMailer.with(user: user, old_email_address: old_email_address, user_agent: user_agent,
            changed_at: Time.current).email_address_changed.deliver_later
          form
        end

        private

        def update_email_address(user, new_email_address, form)
          return true if user.update(email_address: new_email_address)

          user.restore_attributes
          form.errors.add(:email_address, :undeliverable)
          false
        end
      end
    end
  end
end
