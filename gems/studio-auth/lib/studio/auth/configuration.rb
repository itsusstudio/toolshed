module Studio
  module Auth
    class Configuration
      class Error < StandardError; end

      REQUIRED = [:app_name, :mail_from, :support_email].freeze

      attr_accessor :app_name, :mail_from, :support_email

      def validate!
        missing = REQUIRED.select { |setting| public_send(setting).blank? }
        if missing.any?
          raise Error, "studio-auth: set #{missing.map { "c.#{it}" }.join(", ")} in config/initializers/studio_auth.rb"
        end

        ReviewAccounts.validate!
      end
    end
  end
end
