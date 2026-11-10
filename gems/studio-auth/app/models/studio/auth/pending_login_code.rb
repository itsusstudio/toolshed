module Studio
  module Auth
    PendingLoginCode = Data.define(:id, :email_address, :dev_code) do
      self::SESSION_KEY = :studio_auth_pending

      class << self
        def remember_in(session, issued, email_address:)
          session[self::SESSION_KEY] = {
            "id" => issued.id,
            "email_address" => email_address,
            "dev_code" => (issued.code if include_dev_code?)
          }.compact
        end

        def from_session(session)
          stored = session[self::SESSION_KEY]
          return if !stored.is_a?(Hash) || stored["id"].blank?

          new(id: stored["id"], email_address: stored["email_address"], dev_code: stored["dev_code"])
        end

        # Separate from Rails.env so a test can turn on just the dev code.
        def include_dev_code?
          ::Rails.env.development?
        end

        def forget(session)
          session.delete(self::SESSION_KEY)
        end
      end
    end
  end
end
