require "fileutils"

module Studio
  module SiteBintools
    LIBEXEC = File.expand_path("../../libexec", __dir__)
    SCRIPTS = Dir.children(LIBEXEC).sort.freeze
    SETUP = File.expand_path("site_bintools/templates/setup", __dir__)

    class Error < StandardError; end

    class << self
      # bin/studio, the site's Bundler binstub for this gem.
      # Returns the exit status for help and errors; a script replaces the process.
      def cli(argv, root:, out: $stdout)
        script, *args = argv
        return help(out) if script.nil? || ["help", "-h", "--help"].include?(script)
        return install(root, out) if script == "install"
        return help($stderr, error: "unknown script: #{script}") if !SCRIPTS.include?(script)

        Kernel.exec(File.join(LIBEXEC, script), *args, chdir: root)
      end

      def summaries
        SCRIPTS.to_h { [it, summary_of(File.join(LIBEXEC, it))] }
      end

      private

      # Copies bin/setup once and adds the binstub. Setup is copied, not run
      # through bin/studio, because it runs bundle install, before the gem
      # may be installed; the site owns its copy after that.
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

        system("bundle binstubs studio-site-bintools", chdir: root, exception: true)
        out.puts "  create  bin/studio"
        0
      end

      def help(out, error: nil)
        out.puts error, "" if error
        out.puts "Usage: bin/studio <script> [args]", ""
        width = [*SCRIPTS, "install"].map(&:size).max
        summaries.each { |script, summary| out.puts "  #{script.ljust(width)}  #{summary}" }
        out.puts "", "  #{"install".ljust(width)}  Add bin/studio and copy bin/setup into the site (once)"
        error ? 1 : 0
      end

      def summary_of(path)
        File.foreach(path).first(2).last[/\A# Summary: (.+)$/, 1] or raise Error, "no `# Summary:` line under the shebang in #{path}"
      end
    end
  end
end
