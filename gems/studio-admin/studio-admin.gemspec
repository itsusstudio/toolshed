Gem::Specification.new do |spec|
  spec.name = "studio-admin"
  spec.version = File.read(File.expand_path("../../VERSION", __dir__)).strip
  spec.authors = ["ITSUSSTUDIO"]
  spec.email = ["hello@itsusstudio.com"]

  spec.summary = "ITSUSSTUDIO admin area: /admin routes and the studio's admin tools, for staff only"
  spec.description = "A studio_admin route block that puts an app's admin pages, Mission Control Jobs, " \
    "Flipper UI and PgHero under /admin, behind studio-auth staff access."
  spec.homepage = "https://github.com/itsusstudio/toolshed/tree/main/gems/studio-admin"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*.rb", "app/**/*", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "railties", ">= 8.1"
  spec.add_dependency "actionpack", ">= 8.1"
  spec.add_dependency "studio-auth"
  spec.add_dependency "mission_control-jobs", "~> 1.3"
  spec.add_dependency "flipper-ui", "~> 1.4"
  spec.add_dependency "pghero", "~> 4.1"
end
