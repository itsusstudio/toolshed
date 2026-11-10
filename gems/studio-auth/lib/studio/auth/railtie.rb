module Studio
  module Auth
    class Railtie < ::Rails::Railtie
      ROOT = File.expand_path("../../..", __dir__)

      # rate_limit counts in the controller cache store. A null store turns
      # every limit off; a memory store gives each process its own count.
      config.after_initialize do
        store = ActionController::Base.cache_store
        if ::Rails.env.production? && (store.is_a?(ActiveSupport::Cache::NullStore) || store.is_a?(ActiveSupport::Cache::MemoryStore))
          raise Configuration::Error, "studio-auth: rate limits need a shared cache store in production, like Solid Cache"
        end
      end

      initializer "studio_auth.i18n" do |app|
        app.config.i18n.load_path += Dir[File.join(ROOT, "config/locales/*.yml")]
      end

      config.to_prepare { Locales.fill_regional }

      initializer "studio_auth.routes" do
        ActionDispatch::Routing::Mapper.include Routes
      end

      # Pages belong to the app (the install generator writes them); only the
      # mail templates are read from the gem.
      initializer "studio_auth.mail_views" do
        views = File.join(ROOT, "app/views")
        ActiveSupport.on_load(:action_mailer) { append_view_path views }
      end

      # Rails' default filter list misses "code", and review account codes
      # never rotate.
      initializer "studio_auth.filter_parameters" do |app|
        app.config.filter_parameters += FILTER_PARAMETERS
      end

      initializer "studio_auth.mailer_previews", before: "action_mailer.set_configs" do |app|
        app.config.action_mailer.preview_paths = Array(app.config.action_mailer.preview_paths) + [File.join(__dir__, "previews")]
      end

      initializer "studio_auth.validate", after: :load_config_initializers do
        Auth.config.validate!
      end
    end
  end
end
