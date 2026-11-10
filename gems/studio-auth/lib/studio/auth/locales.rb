module Studio
  module Auth
    module Locales
      SHIPPED = [:en, :fr, :nl].freeze
      DIRECTORY = File.expand_path("../../../config/locales", __dir__)

      class << self
        # Apps often offer only regional locales (fr-CA, fr-FR). With
        # enforce_available_locales, I18n drops the gem's bare `fr` file at
        # load, so read it from disk and store it under each regional locale
        # that has no strings of its own.
        def fill_regional
          I18n.available_locales.each do |locale|
            base = locale.to_s.split("-").first.to_sym
            next if locale == base || !SHIPPED.include?(base) || stored?(locale)

            I18n.backend.store_translations(locale, studio_auth: file_strings(base))
          end
        end

        private

        def file_strings(base)
          YAML.load_file(File.join(DIRECTORY, "#{base}.yml")).dig(base.to_s, "studio_auth")
        end

        def stored?(locale)
          I18n.exists?("studio_auth.flash.wrong_code", locale: locale) &&
            I18n.t("studio_auth.flash.wrong_code", locale: locale) != I18n.t("studio_auth.flash.wrong_code", locale: :en)
        end
      end
    end
  end
end
