Gem::Specification.new do |spec|
  spec.name = "studio-auth"
  spec.version = File.read(File.expand_path("../../VERSION", __dir__)).strip
  spec.authors = ["ITSUSSTUDIO"]
  spec.email = ["hello@itsusstudio.com"]

  spec.summary = "ITSUSSTUDIO passwordless sign-in: 6-digit email codes and persistent sessions for Rails apps"
  spec.description = "The whole sign-in lifecycle for studio apps: email code login_codes, lockout, expiring database sessions, reauthentication and new-device mail."
  spec.homepage = "https://github.com/itsusstudio/toolshed/tree/main/gems/studio-auth"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*.rb", "lib/**/*.tt", "lib/generators/**/templates/**/*", "app/**/*", "config/locales/*.yml", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "railties", ">= 8.1"
  spec.add_dependency "actionpack", ">= 8.1"
  spec.add_dependency "activejob", ">= 8.1"
  spec.add_dependency "activerecord", ">= 8.1"
  spec.add_dependency "actionmailer", ">= 8.1"
  spec.add_dependency "valid_email2", ">= 7.1"
end
