Gem::Specification.new do |spec|
  spec.name = "studio-billing"
  spec.version = File.read(File.expand_path("../../VERSION", __dir__)).strip
  spec.authors = ["ITSUSSTUDIO"]
  spec.email = ["hello@itsusstudio.com"]

  spec.summary = "ITSUSSTUDIO billing: a Stripe account set up from config/billing.yml, plus Checkout, portal and webhooks"
  spec.description = "Keeps each app's Stripe products, prices, customer portal and webhook endpoint in sync with one " \
    "YAML file, and builds Checkout and portal sessions with the app's branding."
  spec.homepage = "https://github.com/itsusstudio/toolshed/tree/main/gems/studio-billing"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*.rb", "lib/**/*.tt", "lib/tasks/*.rake", "app/**/*", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "railties", ">= 8.0"
  spec.add_dependency "actionpack", ">= 8.0"
  spec.add_dependency "activejob", ">= 8.0"
  spec.add_dependency "activerecord", ">= 8.0"
  spec.add_dependency "money", ">= 7.0"
  spec.add_dependency "stripe", ">= 21.0"
end
