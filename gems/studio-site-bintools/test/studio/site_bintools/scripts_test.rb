require "test_helper"

class Studio::SiteBintools::ScriptsTest < Minitest::Test
  include SiteHelper

  def test_lint_checks_erb_with_herb
    fake "mise"

    _, status = run_script("lint")

    assert status.success?
    assert_equal ["mise exec -- herb-lint --simple .", "mise exec -- herb-format --check ."], calls
  end

  def test_style_fixes_erb_with_herb
    fake "mise"

    run_script("style")

    assert_equal ["mise exec -- herb-lint --simple --fix .", "mise exec -- herb-format ."], calls
  end

  def test_outdated_treats_exit_1_as_a_finding_but_stops_on_other_failures
    fake "bundle", "exit 1"
    fake "npm", "exit 2"

    _, status = run_script("outdated")

    assert_equal 2, status.exitstatus
    assert_equal ["bundle outdated --only-explicit", "npm outdated"], calls
  end

  def test_ci_lints_audits_checks_images_and_builds_for_production
    fake "npm", 'echo "npm BRIDGETOWN_ENV=$BRIDGETOWN_ENV" >> calls.log'
    ["bin/studio", "bin/bridgetown"].each { |command| fake command }
    FileUtils.mkdir_p(File.join(@site, "frontend/styles"))

    output, status = run_script("ci")

    assert status.success?, output
    assert_equal [
      "bin/studio lint",
      "npm audit",
      "npm BRIDGETOWN_ENV=production",
      "bin/studio check-fingerprinted-images",
      "bin/bridgetown clean",
      "npm run esbuild",
      "npm BRIDGETOWN_ENV=production",
      "bin/bridgetown build"
    ], calls
  end

  def test_ci_names_the_failed_step
    fake "bin/studio", "exit 1"

    output, status = run_script("ci")

    refute status.success?
    assert_match "Style: lint failed", output
  end

  def test_check_fingerprinted_images_passes_when_images_go_through_asset_path
    site_file "src/_data/team.yml", "photo: images/team.png\n"
    site_file "src/index.erb", %(<img src="<%= asset_path "images/hero.png" %>">\n)

    output, status = run_script("check-fingerprinted-images")

    assert status.success?, output
  end

  def test_check_fingerprinted_images_reports_every_kind_of_raw_path
    site_file "src/_data/team.yml", "people:\n  - photo: /assets/images/ana.png\n"
    site_file "src/index.erb", %(<img src="<%= person.photo %>">\n<img src="/assets/images/hero.png">\n)

    output, status = run_script("check-fingerprinted-images")

    refute status.success?
    assert_match "src/_data/team.yml: src/_data/team.yml.people[0].photo uses raw path `/assets/images/ana.png`", output
    assert_match %(src/index.erb: <img src="<%= person.photo %>"> does not go through asset_path), output
    assert_match %(src/index.erb: <img src="/assets/images/hero.png"> is a hardcoded raw path), output
  end

  def test_check_fingerprinted_images_honors_the_site_allowlist
    site_file "config/images.yml", <<~YAML
      fingerprinting:
        raw_path_prefixes: [/assets/images/, /screenshots/]
        allowed_raw_paths: [/assets/images/blog/*]
        allowed_unwrapped_expressions: ['\\bbadges\\.']
    YAML
    site_file "src/_data/meta.yml", "og: /assets/images/og-image-fr.png\nshot: /screenshots/a.png\n"
    site_file "src/index.erb", %(<img src="<%= badges.app_store %>">\n<img src="/assets/images/favicon/32.png">\n<img src="/assets/images/blog/a.png">\n)

    output, status = run_script("check-fingerprinted-images")

    refute status.success?
    assert_equal 1, output.scan(/^  - /).size, output
    assert_match "shot uses raw path `/screenshots/a.png`", output
  end
end
