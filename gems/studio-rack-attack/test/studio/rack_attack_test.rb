require "test_helper"

class Studio::RackAttackTest < ActionDispatch::IntegrationTest
  EDGE = "162.158.1.1"

  def app
    DummyApp
  end

  setup do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rack::Attack.enabled = false }

  test "it is off unless ENABLE_RACK_ATTACK is true" do
    refute ENV["ENABLE_RACK_ATTACK"] == "true"
    Rack::Attack.enabled = false

    get "/.env"

    assert_response :ok
  end

  test "rack-attack's middleware is in the stack once" do
    assert_equal 1, DummyApp.middleware.count { it.klass == Rack::Attack }
  end

  test "scanner probes get a plain 404 and are reported" do
    ["/.env", "/app/.git/config", "/wp-login.php", "/../etc/passwd", "/%2e%2e/secret", "/config/master.key",
      "/index.php", "/latest/meta-data/iam/", "/db.bak"].each do |path|
      get path

      assert_response :not_found, path
      assert_equal "Not Found\n", response.body, path
    end
    assert_event_logged "request_blocked", level: :warn, payload: {rule: "studio/scanner_paths", path: "/.env"}
  end

  test "ordinary paths are not blocked" do
    get "/recipes"

    assert_response :ok
  end

  test "through a Cloudflare edge the throttle keys on CF-Connecting-IP" do
    300.times { get "/recipes", headers: {"REMOTE_ADDR" => EDGE, "CF-Connecting-IP" => "203.0.113.1"} }
    get "/recipes", headers: {"REMOTE_ADDR" => EDGE, "CF-Connecting-IP" => "203.0.113.2"}
    assert_response :ok

    get "/recipes", headers: {"REMOTE_ADDR" => EDGE, "CF-Connecting-IP" => "203.0.113.1"}
    assert_response :too_many_requests
    assert_event_logged "request_throttled", payload: {rule: "studio/req/ip", method: "GET", path: "/recipes", client_ip: "203.0.113.1"}
  end

  test "CF-Connecting-IP from outside Cloudflare is ignored, so rotating it doesn't dodge the throttle" do
    300.times { |i| get "/recipes", headers: {"REMOTE_ADDR" => "198.51.100.7", "CF-Connecting-IP" => "203.0.113.#{i % 250}"} }
    get "/recipes", headers: {"REMOTE_ADDR" => "198.51.100.7", "CF-Connecting-IP" => "203.0.113.251"}

    assert_response :too_many_requests
  end

  test "a spoofed Forwarded header behind our load balancer can't pose as a Cloudflare edge" do
    headers = {"REMOTE_ADDR" => "10.0.0.5", "HTTP_X_FORWARDED_FOR" => "198.51.100.8", "HTTP_FORWARDED" => "for=#{EDGE}"}

    300.times { |i| get "/recipes", headers: headers.merge("CF-Connecting-IP" => "203.0.113.#{i % 250}") }
    get "/recipes", headers: headers.merge("CF-Connecting-IP" => "203.0.113.251", "HTTP_FORWARDED" => "for=198.51.100.99")

    assert_response :too_many_requests
  end

  test "through our load balancer, a Cloudflare edge in X-Forwarded-For is trusted" do
    headers = {"REMOTE_ADDR" => "10.0.0.5", "HTTP_X_FORWARDED_FOR" => "203.0.113.50, #{EDGE}"}

    300.times { get "/recipes", headers: headers.merge("CF-Connecting-IP" => "203.0.113.1") }
    get "/recipes", headers: headers.merge("CF-Connecting-IP" => "203.0.113.2")
    assert_response :ok

    get "/recipes", headers: headers.merge("CF-Connecting-IP" => "203.0.113.1")
    assert_response :too_many_requests
  end

  test "#remote_ip is the visitor behind a Cloudflare edge and our load balancer" do
    get "/remote_ip", headers: {"REMOTE_ADDR" => "10.0.0.5", "HTTP_X_FORWARDED_FOR" => "203.0.113.50, #{EDGE}"}

    assert_equal "203.0.113.50", response.body
  end

  test "#remote_ip is the visitor when a Cloudflare edge connects directly" do
    get "/remote_ip", headers: {"REMOTE_ADDR" => EDGE, "HTTP_X_FORWARDED_FOR" => "203.0.113.50"}

    assert_equal "203.0.113.50", response.body
  end

  test "#remote_ip ignores X-Forwarded-For from a client that bypassed Cloudflare" do
    get "/remote_ip", headers: {"REMOTE_ADDR" => "10.0.0.5", "HTTP_X_FORWARDED_FOR" => "203.0.113.50, 198.51.100.7"}

    assert_equal "198.51.100.7", response.body
  end

  test ".cloudflare? matches IPv4 and IPv6 edges and rejects anything else" do
    assert Studio::RackAttack.cloudflare?(EDGE)
    assert Studio::RackAttack.cloudflare?("2606:4700::1")
    refute Studio::RackAttack.cloudflare?("198.51.100.7")
    refute Studio::RackAttack.cloudflare?("not an ip")
  end

  test "without CF-Connecting-IP the throttle keys on the request IP" do
    300.times { get "/recipes", headers: {"REMOTE_ADDR" => "198.51.100.1"} }
    get "/recipes", headers: {"REMOTE_ADDR" => "198.51.100.1"}

    assert_response :too_many_requests
  end

  test "health checks, assets and Active Storage files are never throttled" do
    301.times { get "/up" }
    assert_response :ok

    301.times { get "/assets/app.css" }
    assert_response :ok

    301.times { get "/rails/active_storage/blobs/redirect/abc/photo.webp" }
    assert_response :ok
  end

  test "a throttled page request gets public/429.html, with no Retry-After" do
    301.times { get "/recipes", headers: {"Accept" => "text/html"} }

    assert_response :too_many_requests
    assert_includes response.body, "Slow down"
    assert_nil response.headers["Retry-After"]
  end

  test "any other throttled request gets plain text" do
    301.times { get "/recipes", headers: {"Accept" => "application/json"} }

    assert_response :too_many_requests
    assert_equal "Too many requests.\n", response.body
  end
end
