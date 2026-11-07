module Studio
  module AppBintools
    LIBEXEC = File.expand_path("../../libexec", __dir__)
    SCRIPTS = Dir.children(LIBEXEC).sort.freeze

    HELP_FLAGS = ["-h", "--help"].freeze

    class Error < StandardError; end

    class << self
      # bin/studio, the app's Bundler binstub for this gem. The bundle is
      # set up but Rails is not loaded, which keeps it fast enough for git
      # hooks.
      # Returns the exit status for help and errors; a script replaces the process.
      def cli(argv, root:, out: $stdout)
        script, *args = argv
        return help(out) if script.nil? || HELP_FLAGS.include?(script) || argv == ["help"]
        return script_help(args.first, out) if script == "help"
        return help($stderr, error: "unknown script: #{script}") if !SCRIPTS.include?(script)
        # Most scripts ignore --help, so passing it through would run them:
        # `db-reset --help` would reset the database.
        return script_help(script, out) if args.intersect?(HELP_FLAGS)

        Kernel.exec(env(root), File.join(LIBEXEC, script), *args, chdir: root)
      end

      def env(root)
        {
          "STUDIO_APP" => app_name(root),
          "STUDIO_FLIPPER" => (Gem.loaded_specs.key?("flipper") ? "1" : nil)
        }
      end

      def summaries
        SCRIPTS.to_h { [it, header(it)[:summary]] }
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

      def script_help(script, out)
        return help($stderr, error: "unknown script: #{script}") if !SCRIPTS.include?(script)

        out.puts "Usage: bin/studio #{header(script)[:usage]}", "", header(script)[:summary]
        0
      end

      # `# Summary:` on the line under the shebang, then an optional `# Usage:`.
      def header(script)
        _, summary, usage = File.foreach(File.join(LIBEXEC, script)).first(3)
        summary = summary.to_s[/\A# Summary: (.+)$/, 1] or raise Error, "no `# Summary:` line under the shebang in #{script}"
        {summary: summary, usage: usage.to_s[/\A# Usage: (.+)$/, 1] || script}
      end
    end
  end
end
