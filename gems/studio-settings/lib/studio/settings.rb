require "rails"

module Studio
  # config/app.yml, through config_for, as nested Data objects: every level has
  # dot access (AppSettings.product.name), and a mistyped or missing key raises
  # NoMethodError instead of returning nil.
  module Settings
    class << self
      def build(values)
        return values if !values.is_a?(Hash)

        attributes = values.transform_values { build(it) }
        Data.define(*attributes.keys).new(**attributes)
      end

      # Another environment's settings, for tests that check production values.
      def for_env(env, app: ::Rails.application)
        build(app.config_for(:app, env: env))
      end
    end
  end
end
