Gem::Specification.new do |spec|
  spec.name = "studio-cache"
  spec.version = File.read(File.expand_path("../../VERSION", __dir__)).strip
  spec.authors = ["ITSUSSTUDIO"]
  spec.email = ["mackenzie@itsusstudio.com"]

  spec.summary = "ITSUSSTUDIO caches: one class per cache over Rails.cache, each behind a Flipper killswitch"
  spec.description = "Declare a cache's TTL and version on a class; it builds its keys the Rails way and reads its killswitch flag from its name."
  spec.homepage = "https://github.com/itsusstudio/toolshed/tree/main/gems/studio-cache"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*.rb", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "railties", ">= 8.0"
  spec.add_dependency "flipper", ">= 1.3"
end
