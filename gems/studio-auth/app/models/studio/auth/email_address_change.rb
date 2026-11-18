module Studio
  module Auth
    EmailAddressChange = Data.define(:user_id, :new_email_address, :step, :code_id, :dev_code) do
      self::SESSION_KEY = :studio_auth_email_address_change
      self::STEPS = [:current, :new].freeze

      class << self
        def store_in_rails_session(session, user:, new_email_address:, step:, issued:)
          session[self::SESSION_KEY] = {
            "user_id" => user.id,
            "new_email_address" => new_email_address,
            "step" => step.to_s,
            "code_id" => issued.id,
            "dev_code" => (issued.code if PendingLoginCode.include_dev_code?)
          }.compact
        end

        def from_rails_session(session, user:)
          stored = session[self::SESSION_KEY]
          return if !stored.is_a?(Hash) || stored["user_id"] != user&.id || stored["code_id"].blank?

          step = self::STEPS.find { it.to_s == stored["step"] }
          return if step.nil?

          new(user_id: stored["user_id"], new_email_address: stored["new_email_address"], step: step,
            code_id: stored["code_id"], dev_code: stored["dev_code"])
        end

        def delete_from_rails_session(session)
          session.delete(self::SESSION_KEY)
        end
      end

      def code_sent_to(user)
        (step == :current) ? user.email_address : new_email_address
      end
    end
  end
end
