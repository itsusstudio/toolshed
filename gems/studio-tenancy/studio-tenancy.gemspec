Gem::Specification.new do |spec|
  spec.name = "studio-tenancy"
  spec.version = File.read(File.expand_path("../../VERSION", __dir__)).strip
  spec.authors = ["ITSUSSTUDIO"]
  spec.email = ["hello@itsusstudio.com"]

  spec.summary = "ITSUSSTUDIO tenancy: organizations, memberships and current_organization for Rails apps"
  spec.description = "The studio tenant model on top of studio-auth: a personal organization per user, " \
    "memberships with roles, a default organization and current_organization in controllers."
  spec.homepage = "https://github.com/itsusstudio/toolshed/tree/main/gems/studio-tenancy"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*.rb", "lib/generators/**/templates/**/*", "app/**/*", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "railties", ">= 8.1"
  spec.add_dependency "actionpack", ">= 8.1"
  spec.add_dependency "activerecord", ">= 8.1"
  spec.add_dependency "studio-auth"
end
