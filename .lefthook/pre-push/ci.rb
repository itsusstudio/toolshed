#!/usr/bin/env ruby
# Gates pushes to main only, running CI for changed gems; a shared root file
# change runs every gem.

repo_root = File.expand_path("../..", __dir__)
shared = ["Gemfile", "Gemfile.lock", ".ruby-version", "mise.toml", "VERSION", ".standard.yml", "bin/ci", "bin/lint"]
status = 0

$stdin.each_line do |line|
  _local_ref, local_sha, remote_ref, remote_sha = line.split
  next if remote_ref != "refs/heads/main"

  range = (remote_sha =~ /[^0]/) ? "#{remote_sha}..#{local_sha}" : local_sha

  fixups = `git log #{range} -E --grep='^(fixup|squash|amend)!' --format='  %h %s'`
  if !fixups.strip.empty?
    puts "🚫 Push to main blocked — squash these autosquash commits first:"
    puts fixups
    puts "  git rebase -i --autosquash origin/main   (or push --no-verify)"
    exit 1
  end

  changed = `git diff --name-only #{range}`.lines.map(&:chomp)
  all_gems = Dir["#{repo_root}/gems/*/"].map { |dir| File.basename(dir) }
  gems =
    if changed.any? { |file| shared.include?(file) }
      all_gems
    else
      all_gems.select { |name| changed.any? { |file| file.start_with?("gems/#{name}/") } }
    end
  next if gems.empty?

  # A gem whose gemspec depends on a changed gem can break too, so test it.
  specs = all_gems.to_h { |name| [name, Gem::Specification.load("#{repo_root}/gems/#{name}/#{name}.gemspec")] }
  queue = gems.dup
  while (name = queue.shift)
    dependents = specs.select { |_, spec| spec.dependencies.any? { it.name == name } }.keys
    (dependents - gems).each do |dependent|
      gems << dependent
      queue << dependent
    end
  end

  puts "🔍 Testing #{gems.join(", ")} (changed, or depending on a changed gem)"
  # The hook inherits the caller's Ruby; mise x re-resolves the repo's pins.
  status = 1 if !system("cd #{repo_root} && mise x -- bin/ci #{gems.join(" ")}")
end

exit status
