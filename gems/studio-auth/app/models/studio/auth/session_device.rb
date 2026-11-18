module Studio
  module Auth
    class SessionDevice
      BROWSERS = [
        ["Edge", /Edg(e|A|iOS)?\//],
        ["Firefox", /Firefox\/|FxiOS\//],
        ["Chrome", /Chrome\/|CriOS\//],
        ["Safari", /Safari\//]
      ].freeze

      OPERATING_SYSTEMS = [
        ["iPadOS", /iPad/],
        ["iOS", /iPhone|iPod/],
        ["Android", /Android/],
        ["macOS", /Macintosh|Mac OS X/],
        ["Windows", /Windows/],
        ["ChromeOS", /CrOS/],
        ["Linux", /Linux/]
      ].freeze

      attr_reader :kind, :name

      class << self
        def from_user_agent(user_agent)
          user_agent = user_agent.to_s

          if user_agent.include?("Hotwire Native iOS")
            tablet = user_agent.match?(/iPad|Macintosh/)
            return new(kind: tablet ? :tablet : :phone,
              name: native_app_name(tablet ? "iPad" : "iPhone"))
          end
          if user_agent.include?("Hotwire Native Android")
            return new(kind: :phone, name: native_app_name("Android"))
          end

          browser = first_match(BROWSERS, user_agent)
          os = first_match(OPERATING_SYSTEMS, user_agent)
          return new(kind: :computer, name: I18n.t("studio_auth.session_device.unknown")) if browser.nil? && os.nil?

          new(kind: kind_for(os, user_agent), name: browser_name(browser, os))
        end

        private

        def native_app_name(platform)
          I18n.t("studio_auth.session_device.app_for", app_name: Auth.config.app_name, platform: platform)
        end

        def browser_name(browser, os)
          return browser || os if browser.nil? || os.nil?

          I18n.t("studio_auth.session_device.browser_on", browser: browser, os: os)
        end

        def kind_for(os, user_agent)
          return :tablet if os == "iPadOS" || (os == "Android" && !user_agent.include?("Mobile"))
          return :phone if os == "iOS" || os == "Android"

          :computer
        end

        def first_match(candidates, user_agent)
          candidates.find { |_, pattern| user_agent.match?(pattern) }&.first
        end
      end

      def initialize(kind:, name:)
        @kind = kind
        @name = name
      end
    end
  end
end
