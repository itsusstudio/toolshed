module Studio
  module Admin
    class Configuration
      class Error < StandardError; end

      # Sessions can last for years, so a stolen cookie must not be able to
      # change data through the admin area for that long.
      WRITE_SIGN_IN_MAX_AGE_LIMIT = 12.hours

      attr_accessor :read_sign_in_max_age, :write_sign_in_max_age

      def initialize
        @read_sign_in_max_age = WRITE_SIGN_IN_MAX_AGE_LIMIT
        @write_sign_in_max_age = WRITE_SIGN_IN_MAX_AGE_LIMIT
      end

      def sign_in_max_age(write:)
        write ? write_sign_in_max_age : read_sign_in_max_age
      end

      def validate_config!
        [:read_sign_in_max_age, :write_sign_in_max_age].each do |setting|
          next if public_send(setting).is_a?(ActiveSupport::Duration)

          raise Error, "studio-admin: c.#{setting} takes a duration, e.g. 12.hours"
        end

        if write_sign_in_max_age > WRITE_SIGN_IN_MAX_AGE_LIMIT
          raise Error, "studio-admin: c.write_sign_in_max_age can be at most #{WRITE_SIGN_IN_MAX_AGE_LIMIT.inspect}"
        end
      end
    end
  end
end
