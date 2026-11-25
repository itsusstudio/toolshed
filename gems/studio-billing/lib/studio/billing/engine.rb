module Studio
  module Billing
    class Engine < ::Rails::Engine
      rake_tasks do
        load File.expand_path("../../tasks/studio_billing.rake", __dir__)
      end

      config.after_initialize do
        if File.exist?(Billing.config.catalog_path)
          Billing.config.validate_usage!(Billing.catalog)
        end
      end

      initializer "studio_billing.routes" do
        ActionDispatch::Routing::Mapper.include Routes
      end

      initializer "studio_billing.configure", after: :load_config_initializers do
        config = Billing.config
        config.validate_config!

        Stripe.open_timeout = config.open_timeout
        Stripe.read_timeout = config.read_timeout
        Stripe.write_timeout = config.write_timeout
      end
    end
  end
end
