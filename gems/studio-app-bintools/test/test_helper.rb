require "rails"
require "rails/generators"
require "rails/generators/test_case"
require "studio/app_bintools"
require "generators/studio/app_bintools/install_generator"
require "minitest/autorun"
require "mocha/minitest"
require "open3"
require "stringio"
require "tmpdir"

# Runs a libexec script inside a throwaway app dir, with every external
# command it touches (docker, op, git, mise, bin/rails, ...) replaced by a
# fake that logs its arguments to calls.log.
module ScriptHelper
  def setup
    super
    @app = Dir.mktmpdir("app")
    @fakes = File.join(@app, ".fakes")
    FileUtils.mkdir_p([@fakes, File.join(@app, "bin")])
  end

  def teardown
    FileUtils.remove_entry(@app)
    super
  end

  def fake(command, body = "")
    path = command.start_with?("bin/") ? File.join(@app, command) : File.join(@fakes, command)
    File.write(path, <<~SH)
      #!/usr/bin/env bash
      echo "#{command} $*" >> "#{calls_log}"
      #{body}
    SH
    File.chmod(0o755, path)
  end

  def run_script(name, *args, env: {})
    env = {"STUDIO_APP" => "belly", "STUDIO_FLIPPER" => nil, "PATH" => "#{@fakes}:#{ENV["PATH"]}"}.merge(env)
    output, status = Open3.capture2e(env, File.join(Studio::AppBintools::LIBEXEC, name), *args, chdir: @app)
    [output, status]
  end

  def calls
    File.exist?(calls_log) ? File.readlines(calls_log, chomp: true) : []
  end

  private

  def calls_log = File.join(@app, "calls.log")
end
