module Studio
  module Auth
    module ReviewAccounts
      CODE_FORMAT = /\A\d{6}\z/
      LIMIT = 2

      class << self
        def code_for(email_address)
          all[Auth.normalize_email(email_address)]
        end

        def include?(email_address)
          all.key?(Auth.normalize_email(email_address))
        end

        def all
          @all ||= read.freeze
        end

        def reset!
          @all = nil
        end

        def validate!
          if all.size > LIMIT
            fail!("allows at most #{LIMIT} accounts")
          end
          fail!("has an entry with no email_address") if all.key?("")

          bad = all.reject { |_email, code| code.match?(CODE_FORMAT) }.keys
          return if bad.empty?

          fail!("login_code must be 6 digits for #{bad.join(", ")}")
        end

        private

        def fail!(problem)
          raise Configuration::Error, "studio-auth: review_accounts #{problem}. Run bin/rails credentials:edit --environment #{::Rails.env}"
        end

        def read
          entries = ::Rails.application.credentials.dig(:studio_auth, :review_accounts) || []
          entries.to_h do |entry|
            entry = entry.to_h.symbolize_keys
            [Auth.normalize_email(entry[:email_address]), entry[:login_code].to_s]
          end
        end
      end
    end
  end
end
