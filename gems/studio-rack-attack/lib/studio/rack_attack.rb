require "rails"
require "ipaddr"
require "rack/attack"
require "studio/monitoring"

module Studio
  module RackAttack
    SCANNER_PATHS = %r{
      # Dotfile / VCS / secret exposure
        (^|/)\.env
      | (^|/)\.git
      | /\.aws/
      | /\.ssh/
      | (^|/)\.htaccess
      | (^|/)\.htpasswd
      | (^|/)\.DS_Store

      # Rails secret files, none served from public/
      | /master\.key\b
      | /(database|secrets)\.yml\b
      | /credentials(/[a-z0-9_-]+)?\.yml(\.enc)?\b

      # Backup / swap files
      | \.(bak|swp|swo|orig)(\z|/)
      | ~\z

      # Path traversal, literal and URL-encoded
      | \.\./
      | \.\.\\
      | %2e%2e
      | \.\.%2f
      | \.\.%5c
      | %00

      # WordPress
      | /wp-(admin|login|content|includes|json|config)
      | /xmlrpc\.php

      # phpMyAdmin / PHP info
      | /phpmyadmin
      | /phpinfo

      # PHP / ASP / JSP / CGI probes
      | \.(php|aspx?|jsp|cgi)\b

      # Other CMS / install probes
      | /administrator/
      | /(install|setup|admin)\.php
      | /joomla
      | /drupal

      # CVE-driven hot endpoints
      | /_ignition/execute-solution
      | /actuator/(env|heapdump|threaddump|mappings)
      | /manager/html
      | /host-manager/html
      | /owa/
      | /ecp/

      # Tomcat / Struts / CGI dirs
      | /cgi-bin/
      | /struts(2)?/

      # Cloud-metadata SSRF tells
      | 169\.254\.169\.254
      | /latest/meta-data/
    }ix

    # One page can load dozens of images through Active Storage redirects.
    UNTHROTTLED_PATH_PREFIXES = ["/assets/", "/packs/", "/rails/active_storage/"].freeze

    # https://www.cloudflare.com/ips/
    CLOUDFLARE_RANGES = [
      "173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22",
      "141.101.64.0/18", "108.162.192.0/18", "190.93.240.0/20", "188.114.96.0/20",
      "197.234.240.0/22", "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13",
      "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22",
      "2400:cb00::/32", "2606:4700::/32", "2803:f800::/32", "2405:b500::/32",
      "2405:8100::/32", "2a06:98c0::/29", "2c0f:f248::/32"
    ].map { IPAddr.new(it) }.freeze

    # Behind Cloudflare, the peer is an edge IP shared by thousands of
    # unrelated clients, and CF-Connecting-IP holds the real one. The header is
    # only trusted from a Cloudflare edge: the origin is reachable directly
    # too, and there anyone could send a new value per request to dodge every
    # throttle.
    module ClientIp
      def client_ip
        forwarded = env["HTTP_CF_CONNECTING_IP"].presence
        (forwarded && RackAttack.cloudflare?(peer_ip)) ? forwarded : peer_ip
      end

      # The nearest untrusted hop: REMOTE_ADDR, or the last X-Forwarded-For
      # entry our own load balancer appended. Unlike req.ip, it ignores the
      # client-supplied Forwarded header, which Rack reads first.
      def peer_ip
        hops = [*env["HTTP_X_FORWARDED_FOR"].to_s.split(","), env["REMOTE_ADDR"]].map { it.to_s.strip }.compact_blank
        hops.rfind { !trusted_proxy?(it) } || hops.first
      end
    end

    class RemoteIp
      def initialize(app)
        @app = app
      end

      def call(env)
        env["action_dispatch.remote_ip"] = ::Rack::Request.new(env).extend(ClientIp).client_ip
        @app.call(env)
      end
    end

    class << self
      def cloudflare?(address)
        address = IPAddr.new(address.to_s)
        CLOUDFLARE_RANGES.any? { it.include?(address) }
      rescue IPAddr::Error
        false
      end

      def install
        ::Rack::Attack::Request.include(ClientIp)
        ::Rack::Attack.enabled = ENV["ENABLE_RACK_ATTACK"] == "true"

        ::Rack::Attack.safelist("studio/health_check") { |req| req.path == "/up" }

        # A 404 alone. Banning the source IP would key on a shared Cloudflare
        # edge IP and lock out unrelated clients.
        ::Rack::Attack.blocklist("studio/scanner_paths") { |req| req.path.match?(SCANNER_PATHS) }

        # Catches volumetric scrapers; people browse far below this.
        ::Rack::Attack.throttle("studio/req/ip", limit: 300, period: 1.minute) do |req|
          req.client_ip if !req.path.start_with?(*UNTHROTTLED_PATH_PREFIXES)
        end

        ::Rack::Attack.throttled_responder = method(:throttled_response)
        # 404, not 403, so a probe learns nothing about the blocklist.
        ::Rack::Attack.blocklisted_responder = ->(_req) { [404, {"content-type" => "text/plain"}, ["Not Found\n"]] }

        ActiveSupport::Notifications.subscribe(/\A(throttle|blocklist)\.rack_attack\z/) do |name, *, payload|
          report(name, payload[:request])
        end
      end

      private

      # No Retry-After: it tells an attacker exactly when the window reopens.
      def throttled_response(req)
        page = ::Rails.public_path.join("429.html")
        if req.get_header("HTTP_ACCEPT").to_s.include?("text/html") && page.exist?
          [429, {"content-type" => "text/html; charset=utf-8"}, [page.read]]
        else
          [429, {"content-type" => "text/plain"}, ["Too many requests.\n"]]
        end
      end

      def report(name, req)
        event = name.start_with?("throttle") ? "request_throttled" : "request_blocked"
        Monitoring::Events.warn(event, rule: req.env["rack.attack.matched"], method: req.request_method, path: req.path, client_ip: req.client_ip)
      end
    end
  end
end

require_relative "rack_attack/railtie" if defined?(Rails::Railtie)
