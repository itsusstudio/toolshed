Gem::Specification.new do |spec|
  spec.name = "studio-rack-attack"
  spec.version = File.read(File.expand_path("../../VERSION", __dir__)).strip
  spec.authors = ["ITSUSSTUDIO"]
  spec.email = ["mackenzie@itsusstudio.com"]

  spec.summary = "ITSUSSTUDIO Rack::Attack baseline: client IP behind Cloudflare, scanner blocklist, global throttle"
  spec.description = "The Rack::Attack rules and responses every studio app shares; apps add their own throttles on top."
  spec.homepage = "https://github.com/itsusstudio/toolshed/tree/main/gems/studio-rack-attack"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*.rb", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "railties", ">= 8.0"
  spec.add_dependency "rack-attack", ">= 6.7"
  spec.add_dependency "studio-monitoring"
end
