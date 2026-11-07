require "flipper/ui"

module Studio
  module Flags
    class Railtie < ::Rails::Railtie
      rake_tasks do
        load File.expand_path("../../tasks/flipper.rake", __dir__)
      end

      initializer "studio_flags.ui" do
        Flipper::UI.configure do |ui|
          # Anything the UI created or removed would be undone by the next sync.
          ui.feature_creation_enabled = false
          ui.feature_removal_enabled = false
          ui.descriptions_source = ->(_keys) { Flags.descriptions }
          ui.banner_text = ::Rails.env.titleize
          ui.banner_class = ::Rails.env.local? ? "success" : "danger"
        end
      end
    end
  end
end
