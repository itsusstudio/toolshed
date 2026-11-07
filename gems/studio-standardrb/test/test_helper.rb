require "studio/standardrb"
require "minitest/autorun"
require "json"
require "open3"
require "tmpdir"

# Runs the real standardrb CLI over a snippet, in a throwaway project whose
# .standard.yml lists only this plugin, the way an app uses it.
module LintHelper
  def offenses(source, fix: false)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".standard.yml"), "plugins:\n  - studio-standardrb\n")
      File.write(File.join(dir, "subject.rb"), source)
      args = ["standardrb", "--format", "json", *(fix ? ["--fix-unsafely"] : []), "subject.rb"]
      output, = Open3.capture2e(*args, chdir: dir)
      json = JSON.parse(output[/\{.*\}/m] || raise("standardrb failed: #{output}"))
      @fixed = File.read(File.join(dir, "subject.rb"))
      json.fetch("files").flat_map { |file| file.fetch("offenses") }.map { |offense| offense.fetch("cop_name") }
    end
  end

  def fixed(source)
    offenses(source, fix: true)
    @fixed
  end
end
