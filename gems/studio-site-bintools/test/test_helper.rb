require "studio/site_bintools"
require "minitest/autorun"
require "mocha/minitest"
require "fileutils"
require "open3"
require "stringio"
require "tmpdir"

# Runs a libexec script inside a throwaway site dir, with every external
# command it touches (mise, npm, magick, bin/bridgetown, ...) replaced by a
# fake that logs its arguments to calls.log.
module SiteHelper
  def setup
    super
    @site = Dir.mktmpdir("site")
    @fakes = File.join(@site, ".fakes")
    FileUtils.mkdir_p([@fakes, File.join(@site, "bin")])
  end

  def teardown
    FileUtils.remove_entry(@site)
    super
  end

  def fake(command, body = "")
    path = command.start_with?("bin/") ? File.join(@site, command) : File.join(@fakes, command)
    File.write(path, <<~SH)
      #!/usr/bin/env bash
      echo "#{command} $*" >> "#{calls_log}"
      #{body}
    SH
    File.chmod(0o755, path)
  end

  def site_file(relative, content)
    path = File.join(@site, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def run_script(name, *args, env: {})
    env = {"PATH" => "#{@fakes}:#{ENV["PATH"]}", "NO_COLOR" => "1"}.merge(env)
    Open3.capture2e(env, File.join(Studio::SiteBintools::LIBEXEC, name), *args, chdir: @site)
  end

  def calls
    File.exist?(calls_log) ? File.readlines(calls_log, chomp: true) : []
  end

  private

  def calls_log = File.join(@site, "calls.log")
end
