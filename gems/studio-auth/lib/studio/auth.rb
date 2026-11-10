require "rails"
require "active_support"
require "active_support/core_ext"
require "openssl"
require "valid_email2"

require_relative "auth/configuration"
require_relative "auth/typed_input"
require_relative "auth/secrets"
require_relative "auth/app_review_accounts"
require_relative "auth/routes"
require_relative "auth/staff_constraint"

module Studio
  module Auth
    autoload :SecurityTests, "studio/auth/security_tests"
    autoload :TestHelper, "studio/auth/test_helper"

    class << self
      def table_name_prefix = "studio_auth_"

      def configure
        yield config
        config
      end

      def config
        @config ||= Configuration.new
      end
    end
  end
end

require_relative "auth/engine"
