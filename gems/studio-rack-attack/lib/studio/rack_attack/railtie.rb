module Studio
  module RackAttack
    # rack-attack's own Railtie adds the middleware.
    class Railtie < ::Rails::Railtie
      # request.remote_ip follows the same rule as Rack::Attack's client_ip.
      # Trusting Cloudflare ranges in X-Forwarded-For instead would let a
      # client whose own egress is a Cloudflare IP (WARP, Workers) forge it.
      initializer "studio_rack_attack.remote_ip" do |app|
        app.middleware.insert_after ActionDispatch::RemoteIp, RemoteIp
      end

      initializer "studio_rack_attack.install", before: :load_config_initializers do
        RackAttack.install
      end
    end
  end
end
