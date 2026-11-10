require "test_helper"
require "rails/generators/test_case"
require "generators/studio/auth/install_generator"

class Studio::Auth::InstallGeneratorTest < Rails::Generators::TestCase
  tests Studio::Auth::Generators::InstallGenerator
  destination File.join(DUMMY_ROOT, "tmp/generator")

  setup do
    prepare_destination
    FileUtils.mkdir_p(File.join(destination_root, "config"))
    File.write(File.join(destination_root, "config/routes.rb"), "Rails.application.routes.draw do\nend\n")
  end

  test "writes the migration, the initializer and the routes" do
    run_generator

    assert_migration "db/migrate/create_studio_auth.rb", /create_table :studio_auth_login_challenges/
    assert_file "config/initializers/studio_auth.rb", /c\.support_email/
    assert_file "config/routes.rb", /studio_auth/
    assert_file "app/views/studio/auth/sign_ins/new.html.erb", /login_path/
    assert_file "config/locales/studio_auth.en.yml", /\Aen:\n  studio_auth:\n    sign_ins:/
    assert_file "config/locales/studio_auth.fr.yml", /Envoyer le code/
  end
end
