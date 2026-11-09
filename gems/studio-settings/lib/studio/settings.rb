require "rails"

module Studio
  module Settings
    class << self
      def build(values)
        return values if !values.is_a?(Hash)

        attributes = values.transform_values { build(it) }
        Data.define(*attributes.keys).new(**attributes)
      end

      def for_env(env, app: ::Rails.application)
        build(app.config_for(:app, env: env))
      end
    end
  end
end
