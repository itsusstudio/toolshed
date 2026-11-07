Gem::Specification.new do |spec|
  spec.name = "studio-settings"
  spec.version = File.read(File.expand_path("../../VERSION", __dir__)).strip
  spec.authors = ["ITSUSSTUDIO"]
  spec.email = ["mackenzie@itsusstudio.com"]

  spec.summary = "ITSUSSTUDIO settings: config/app.yml as dot-accessible, immutable AppSettings"
  spec.description = "Turns config_for(:app) into nested Data objects, so a mistyped or missing key raises instead of returning nil."
  spec.homepage = "https://github.com/itsusstudio/toolshed/tree/main/gems/studio-settings"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*.rb", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "railties", ">= 8.0"
end
