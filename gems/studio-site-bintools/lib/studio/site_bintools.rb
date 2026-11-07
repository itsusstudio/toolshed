require "fileutils"

module Studio
  module SiteBintools
    LIBEXEC = File.expand_path("../../libexec", __dir__)
    SCRIPTS = Dir.children(LIBEXEC).sort.freeze
    SETUP = File.expand_path("site_bintools/templates/setup", __dir__)

    HELP_FLAGS = ["-h", "--help"].freeze
    # Scripts with their own detailed --help, which bin/studio passes through.
    OWN_HELP = ["optimize-images"].freeze
    INSTALL_SUMMARY = "Copy bin/setup into the site (once)"

    class Error < StandardError; end

    class << self
      # bin/studio, the site's Bundler binstub for this gem.
      # Returns the exit status for help and errors; a script replaces the process.
      def cli(argv, root:, out: $stdout)
        script, *args = argv
        return help(out) if script.nil? || HELP_FLAGS.include?(script) || argv == ["help"]
        return script_help(args.first, out) if script == "help"
        return script_help(script, out) if script == "install" && args.intersect?(HELP_FLAGS)
        return install(root, out) if script == "install"
        return help($stderr, error: "unknown script: #{script}") if !SCRIPTS.include?(script)
        # Most scripts ignore --help, so passing it through would run them.
        return script_help(script, out) if args.intersect?(HELP_FLAGS) && !OWN_HELP.include?(script)

        Kernel.exec(File.join(LIBEXEC, script), *args, chdir: root)
      end

      def summaries
        SCRIPTS.to_h { [it, header(it)[:summary]] }
      end

      private

      # Copied, not run through bin/studio, because bin/setup runs bundle
      # install, before the gem may be installed; the site owns its copy.
      def install(root, out)
        setup = File.join(root, "bin/setup")
        if File.exist?(setup)
          out.puts "  skip    bin/setup (site owns it)"
        else
          FileUtils.mkdir_p(File.dirname(setup))
          FileUtils.cp(SETUP, setup)
          File.chmod(0o755, setup)
          out.puts "  create  bin/setup"
        end
        0
      end

      def help(out, error: nil)
        out.puts error, "" if error
        out.puts "Usage: bin/studio <script> [args]", ""
        width = [*SCRIPTS, "install"].map(&:size).max
        summaries.each { |script, summary| out.puts "  #{script.ljust(width)}  #{summary}" }
        out.puts "", "  #{"install".ljust(width)}  #{INSTALL_SUMMARY}"
        error ? 1 : 0
      end

      def script_help(script, out)
        return script_help_lines("install", INSTALL_SUMMARY, out) if script == "install"
        return help($stderr, error: "unknown script: #{script}") if !SCRIPTS.include?(script)

        script_help_lines(header(script)[:usage], header(script)[:summary], out)
      end

      def script_help_lines(usage, summary, out)
        out.puts "Usage: bin/studio #{usage}", "", summary
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
