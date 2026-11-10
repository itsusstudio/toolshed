module Studio
  module Auth
    module DeviceDescription
      BROWSERS = [["Edge", /Edg\//], ["Firefox", /Firefox\//], ["Chrome", /Chrome\//], ["Safari", /Safari\//]].freeze
      PLATFORMS = [["iPhone", /iPhone/], ["iPad", /iPad/], ["Android", /Android/], ["Mac", /Macintosh/], ["Windows", /Windows/], ["Linux", /Linux/]].freeze
      NATIVE_APP = /(Turbo|Hotwire) Native/

      class << self
        def call(user_agent)
          user_agent = user_agent.to_s
          platform = match(PLATFORMS, user_agent)
          client = user_agent.match?(NATIVE_APP) ? :app : match(BROWSERS, user_agent)

          if client == :app
            I18n.t("studio_auth.devices.app", platform: platform || I18n.t("studio_auth.devices.unknown_platform"))
          elsif client && platform
            I18n.t("studio_auth.devices.browser_on_platform", browser: client, platform: platform)
          else
            I18n.t("studio_auth.devices.unknown")
          end
        end

        private

        def match(table, user_agent)
          table.find { |_name, pattern| user_agent.match?(pattern) }&.first
        end
      end
    end
  end
end
