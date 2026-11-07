module Studio
  module Standardrb
    class Plugin < LintRoller::Plugin
      def about
        LintRoller::About.new(
          name: "studio-standardrb",
          version: VERSION,
          homepage: "https://github.com/itsusstudio/toolshed/tree/main/gems/studio-standardrb",
          description: "ITSUSSTUDIO rules for Standard Ruby"
        )
      end

      def supported?(context)
        true
      end

      def rules(context)
        LintRoller::Rules.new(
          type: :path,
          config_format: :rubocop,
          value: Pathname.new(__dir__).join("../../../config/base.yml")
        )
      end
    end
  end
end
