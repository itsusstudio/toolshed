require "test_helper"

class Studio::Auth::SessionDeviceTest < ActiveSupport::TestCase
  test ".from_user_agent names real devices" do
    {
      "Dummy Hotwire Native iOS; Turbo Native iOS; bridge-components: [form]; Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148" => [:phone, "Dummy for iPhone"],
      "Dummy Hotwire Native iOS; Turbo Native iOS; Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)" => [:tablet, "Dummy for iPad"],
      "Dummy Hotwire Native Android; Turbo Native Android; Mozilla/5.0 (Linux; Android 15; Pixel 8; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/130.0.0.0 Mobile Safari/537.36" => [:phone, "Dummy for Android"],
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" => [:computer, "Chrome on macOS"],
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15" => [:computer, "Safari on macOS"],
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1" => [:phone, "Safari on iOS"],
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/131.0.6778.73 Mobile/15E148 Safari/604.1" => [:phone, "Chrome on iOS"],
      "Mozilla/5.0 (iPad; CPU OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1" => [:tablet, "Safari on iPadOS"],
      "Mozilla/5.0 (Linux; Android 15; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36" => [:phone, "Chrome on Android"],
      "Mozilla/5.0 (Linux; Android 14; SM-X710) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" => [:tablet, "Chrome on Android"],
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:132.0) Gecko/20100101 Firefox/132.0" => [:computer, "Firefox on Windows"],
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0" => [:computer, "Edge on Windows"],
      "Mozilla/5.0 (X11; Linux x86_64; rv:132.0) Gecko/20100101 Firefox/132.0" => [:computer, "Firefox on Linux"],
      "curl/8.7.1" => [:computer, "Unknown device"],
      nil => [:computer, "Unknown device"]
    }.each do |user_agent, (kind, name)|
      device = Studio::Auth::SessionDevice.from_user_agent(user_agent)

      assert_equal [kind, name], [device.kind, device.name], user_agent.inspect
    end
  end

  test ".from_user_agent names the device in the user's language" do
    user_agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    assert_equal "Chrome sur macOS", I18n.with_locale(:fr) { Studio::Auth::SessionDevice.from_user_agent(user_agent).name }
  end
end
