module Studio
  module Auth
    class Configuration
      class Error < StandardError; end
      REQUIRED = [
        :app_name, :mail_from
      ].freeze

      attr_accessor(*REQUIRED)

      SESSION_LIMITS = [:session_idle_timeout, :session_absolute_timeout].freeze

      attr_accessor(*SESSION_LIMITS)

      attr_writer :wordmark_style

      attr_accessor :finish_sign_up_path, :account_settings_path, :support_email_address

      def wordmark_style = @wordmark_style || "serif"

      def validate_config!
        missing = REQUIRED.select { |setting| public_send(setting).blank? }
        missing += SESSION_LIMITS.reject { |setting| public_send(setting).is_a?(ActiveSupport::Duration) }
        if missing.any?
          settings = missing.map { "c.#{it}" }.join(", ")
          raise Error, "studio-auth: set #{settings} in config/initializers/studio_auth.rb " \
            "(session limits take a duration, e.g. 30.days)"
        end

        {finish_sign_up_path: ":setup_path", account_settings_path: ":settings_path"}.each do |setting, example|
          value = public_send(setting)
          next if value.nil? || value.to_s.end_with?("_path")

          raise Error, "studio-auth: c.#{setting} names a path helper like #{example}, not #{value.inspect}"
        end

        if !["serif", "sans"].include?(wordmark_style.to_s)
          raise Error, "studio-auth: c.wordmark_style is \"serif\" or \"sans\", not #{wordmark_style.inspect}"
        end

        AppReviewAccounts.validate_config!
      end
    end
  end
end
