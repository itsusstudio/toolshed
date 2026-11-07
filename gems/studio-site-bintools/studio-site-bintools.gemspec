Gem::Specification.new do |spec|
  spec.name = "studio-site-bintools"
  spec.version = File.read(File.expand_path("../../VERSION", __dir__)).strip
  spec.authors = ["ITSUSSTUDIO"]
  spec.email = ["mackenzie@itsusstudio.com"]

  spec.summary = "ITSUSSTUDIO bin/ scripts for Bridgetown marketing sites"
  spec.description = "The CI, lint, outdated and image scripts every studio marketing site runs, shared instead of copied. Sites run them through bin/studio, a Bundler binstub."
  spec.homepage = "https://github.com/itsusstudio/toolshed/tree/main/gems/studio-site-bintools"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*.rb", "lib/**/templates/*", "libexec/*", "exe/*", "README.md"]
  spec.bindir = "exe"
  spec.executables = ["studio"]
  spec.require_paths = ["lib"]
end
