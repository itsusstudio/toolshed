require "rails/generators"
require "studio/app_bintools"

module Studio
  module AppBintools
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Adds bin/studio and bin/dev-check, and pins the system-test browser."

      def binstub
        run "bundle binstubs studio-app-bintools"
      end

      # Copied, not run through bin/studio: bin/setup runs it before bundle
      # install, when the gem may not be installed yet.
      def dev_check
        copy_file "dev-check", "bin/dev-check"
        chmod "bin/dev-check", 0o755
      end

      def test_browser
        if !File.exist?(File.join(destination_root, ".chrome-for-testing-version"))
          create_file ".chrome-for-testing-version", "stable\n"
        end

        gitignore = File.join(destination_root, ".gitignore")
        entry = "/.chrome-for-testing/"
        if !File.exist?(gitignore)
          create_file ".gitignore", "#{entry}\n"
        elsif !File.readlines(gitignore, chomp: true).include?(entry)
          append_to_file ".gitignore", "#{entry}\n"
        end
      end
    end
  end
end
