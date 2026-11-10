# studio-rack-attack

The Rack::Attack rules every studio app shares. Add `gem "studio-rack-attack"` to the toolshed block; it needs studio-monitoring. The middleware and rules load on their own.

| Rule | Does |
| --- | --- |
| `studio/health_check` | `/up` is never blocked or throttled |
| `studio/scanner_paths` | 404s dotfile, secret-file, path traversal, PHP/WordPress and CVE probes |
| `studio/req/ip` | 300 requests a minute per client IP, assets and Active Storage files excluded |

- On only when `ENABLE_RACK_ATTACK=true`.
- `req.client_ip`, and `request.remote_ip` everywhere in the app, is `CF-Connecting-IP` when the request came through a Cloudflare edge, otherwise the peer. Key per-IP rules on `client_ip`, never `req.ip`. Tests sending `CF-Connecting-IP` need a Cloudflare `REMOTE_ADDR`, such as `162.158.1.1`.
- Treat both as hints for throttling, never proof: any Cloudflare customer can forward a made-up IP.
- A throttled page gets `public/429.html` if the app has one, else plain text.
- Blocks and throttles log `request_blocked` and `request_throttled`.

Add the app's own throttles, and its cache store if it shouldn't be `Rails.cache`:

```ruby
# config/initializers/rack_attack.rb
Rack::Attack.throttle("code_send/ip", limit: 10, period: 1.minute) do |req|
  req.client_ip if req.post? && req.path == "/verification"
end
```
