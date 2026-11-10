Gem::Specification.new do |spec|
  spec.name = "studio-flags"
  spec.version = File.read(File.expand_path("../../VERSION", __dir__)).strip
  spec.authors = ["ITSUSSTUDIO"]
  spec.email = ["hello@itsusstudio.com"]

  spec.summary = "ITSUSSTUDIO feature flags: a config/feature_flags.yml registry synced into Flipper"
  spec.description = "Flags are declared, described and removed in one YAML file; flipper:sync reconciles Flipper with it and the Flipper UI shows the descriptions."
  spec.homepage = "https://github.com/itsusstudio/toolshed/tree/main/gems/studio-flags"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*.rb", "lib/**/*.rake", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "railties", ">= 8.0"
  spec.add_dependency "flipper", ">= 1.3"
  spec.add_dependency "flipper-ui", ">= 1.3"
end
