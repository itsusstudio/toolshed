module Studio
  module RackAttack
    # rack-attack's own Railtie adds the middleware.
    class Railtie < ::Rails::Railtie
      initializer "studio_rack_attack.install", before: :load_config_initializers do
        RackAttack.install
      end
    end
  end
end
