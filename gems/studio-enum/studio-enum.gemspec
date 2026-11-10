Gem::Specification.new do |spec|
  spec.name = "studio-enum"
  spec.version = File.read(File.expand_path("../../VERSION", __dir__)).strip
  spec.authors = ["ITSUSSTUDIO"]
  spec.email = ["hello@itsusstudio.com"]

  spec.summary = "ITSUSSTUDIO enums: named string values with constants, Rails enum mappings and translated labels"
  spec.description = "One class per enum. Declare values once; get constants, lookups, a Rails enum mapping and I18n labels for select boxes."
  spec.homepage = "https://github.com/itsusstudio/toolshed/tree/main/gems/studio-enum"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*.rb", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", ">= 8.0"
end
