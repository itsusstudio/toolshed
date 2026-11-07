module Studio
  module AppBintools
    LIBEXEC = File.expand_path("../../libexec", __dir__)
    SCRIPTS = Dir.children(LIBEXEC).sort.freeze

    class Error < StandardError; end

    class << self
      # bin/studio, the app's Bundler binstub for this gem. The bundle is
      # set up but Rails is not loaded, which keeps it fast enough for git
      # hooks.
      # Returns the exit status for help and errors; a script replaces the process.
      def cli(argv, root:, out: $stdout)
        script, *args = argv
        return help(out) if script.nil? || ["help", "-h", "--help"].include?(script)
        return help($stderr, error: "unknown script: #{script}") if !SCRIPTS.include?(script)

        Kernel.exec(env(root), File.join(LIBEXEC, script), *args, chdir: root)
      end

      def env(root)
        {
          "STUDIO_APP" => app_name(root),
          "STUDIO_FLIPPER" => (Gem.loaded_specs.key?("flipper") ? "1" : nil)
        }
      end

      def summaries
        SCRIPTS.to_h { [it, summary_of(File.join(LIBEXEC, it))] }
      end

      # Same name Rails derives database names from, read without booting
      # the app: config/application.rb's top-level module, underscored.
      def app_name(root)
        source = File.read(File.join(root, "config/application.rb"))
        name = source[/^module (\w+)/, 1] or raise Error, "no app module in #{root}/config/application.rb"
        name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
      end

      private

      def help(out, error: nil)
        out.puts error, "" if error
        out.puts "Usage: bin/studio <script> [args]", ""
        width = SCRIPTS.map(&:size).max
        summaries.each { |script, summary| out.puts "  #{script.ljust(width)}  #{summary}" }
        error ? 1 : 0
      end

      def summary_of(path)
        File.foreach(path).first(2).last[/\A# Summary: (.+)$/, 1] or raise Error, "no `# Summary:` line under the shebang in #{path}"
      end
    end
  end
end
