module Studio
  module Auth
    module AppReviewAccounts
      CODE_FORMAT = /\A\d{6}\z/
      LIMIT = 2

      class << self
        # credentials: studio_auth: app_review_accounts: {email => "123456"}
        def all
          accounts = ::Rails.application.credentials.dig(:studio_auth, :app_review_accounts) || {}
          accounts.to_h do |email_address, code|
            [TypedInput.email_address(email_address), code.to_s]
          end
        end

        def code_for(email_address)
          all[TypedInput.email_address(email_address)]
        end

        def include?(email_address)
          !code_for(email_address).nil?
        end

        def validate_config!
          accounts = all
          fail!("allows at most #{LIMIT} accounts") if accounts.size > LIMIT

          bad = accounts.reject { |_email, code| code.match?(CODE_FORMAT) }.keys
          fail!("codes must be 6 digits, in quotes, for #{bad.join(", ")}") if bad.any?
        end

        private

        def fail!(problem)
          fix = "bin/rails credentials:edit --environment #{::Rails.env}"
          raise Configuration::Error, "studio-auth: app_review_accounts #{problem}. Run #{fix}"
        end
      end
    end
  end
end
