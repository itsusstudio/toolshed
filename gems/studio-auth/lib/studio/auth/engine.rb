module Studio
  module Auth
    class Engine < ::Rails::Engine
      FILTER_PARAMETERS = [/\Acode\z/].freeze

      # rate_limit counts in the controller cache store. A null store turns
      # every limit off; a memory store gives each process its own count.
      config.after_initialize do
        unshared = [ActiveSupport::Cache::NullStore, ActiveSupport::Cache::MemoryStore]
        if ::Rails.env.production? && unshared.any? { ActionController::Base.cache_store.is_a?(it) }
          raise Configuration::Error, "studio-auth: rate limits need a shared cache store in production, " \
            "like Solid Cache"
        end
      end

      initializer "studio_auth.routes" do
        ActionDispatch::Routing::Mapper.include Routes
      end

      # Rails' default filter list misses "code", and review account codes
      # never rotate.
      initializer "studio_auth.filter_parameters" do |app|
        app.config.filter_parameters += FILTER_PARAMETERS
      end

      initializer "studio_auth.mailer_previews", before: "action_mailer.set_configs" do |app|
        previews = File.join(__dir__, "previews")
        app.config.action_mailer.preview_paths = Array(app.config.action_mailer.preview_paths) + [previews]
      end

      initializer "studio_auth.validate", after: :load_config_initializers do
        Auth.config.validate_config!
      end
    end
  end
end
