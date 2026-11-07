module Studio
  module RackAttack
    # rack-attack's own Railtie adds the middleware.
    class Railtie < ::Rails::Railtie
      # Without this, request.remote_ip stops at the Cloudflare edge, so
      # sessions, signatures, rate_limit and logs all record a shared edge IP.
      config.action_dispatch.trusted_proxies = ActionDispatch::RemoteIp::TRUSTED_PROXIES + CLOUDFLARE_RANGES

      initializer "studio_rack_attack.install", before: :load_config_initializers do
        RackAttack.install
      end
    end
  end
end
