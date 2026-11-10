Gem::Specification.new do |spec|
  spec.name = "studio-app-bintools"
  spec.version = File.read(File.expand_path("../../VERSION", __dir__)).strip
  spec.authors = ["ITSUSSTUDIO"]
  spec.email = ["hello@itsusstudio.com"]

  spec.summary = "ITSUSSTUDIO bin/ scripts for Rails apps"
  spec.description = "The dev, database, credentials, lint and deploy scripts every studio app runs, shared instead of copied. Apps run them through bin/studio, a Bundler binstub."
  spec.homepage = "https://github.com/itsusstudio/toolshed/tree/main/gems/studio-app-bintools"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*.rb", "lib/**/*.tt", "lib/**/templates/*", "libexec/*", "exe/*", "README.md"]
  spec.bindir = "exe"
  spec.executables = ["studio"]
  spec.require_paths = ["lib"]

  spec.add_dependency "railties", ">= 8.0"
end
