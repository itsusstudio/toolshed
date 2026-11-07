# studio-rack-attack

The Rack::Attack rules every studio app shares. Add `gem "studio-rack-attack"` to the toolshed block; it needs studio-monitoring. The middleware and rules load on their own.

| Rule | Does |
| --- | --- |
| `studio/health_check` | `/up` is never blocked or throttled |
| `studio/scanner_paths` | 404s dotfile, secret-file, path traversal, PHP/WordPress and CVE probes |
| `studio/req/ip` | 300 requests a minute per client IP, assets and Active Storage files excluded |

- On only when `ENABLE_RACK_ATTACK=true`.
- `req.client_ip` is the real client: `CF-Connecting-IP` when the request came through a Cloudflare edge, otherwise `req.ip`. Key every per-IP rule on it, never on `req.ip`. Tests that send `CF-Connecting-IP` need a Cloudflare `REMOTE_ADDR`, such as `162.158.1.1`.
- Cloudflare's ranges are added to Rails' `trusted_proxies`, so `request.remote_ip` is the visitor, not the edge, everywhere in the app: sessions, `rate_limit`, logs.
- A throttled page request gets `public/429.html` if the app has one, anything else plain text. There is no Retry-After header.
- Blocks and throttles log `request_blocked` and `request_throttled` events with the rule, method, path and client IP.

Add the app's own throttles, and its cache store if it shouldn't be `Rails.cache`:

```ruby
# config/initializers/rack_attack.rb
Rack::Attack.throttle("code_send/ip", limit: 10, period: 1.minute) do |req|
  req.client_ip if req.post? && req.path == "/verification"
end
```
