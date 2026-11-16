source "https://rubygems.org"

Dir[File.join(__dir__, "gems/*/*.gemspec")].each do |gemspec|
  gemspec path: File.dirname(gemspec)
end

gem "rake"
gem "minitest"
gem "mocha"
gem "sqlite3"
gem "actioncable"
gem "propshaft"
gem "studio-uniform", github: "itsusstudio/uniform", branch: "main", glob: "uniform/*.gemspec"

gem "bundler-audit", require: false
