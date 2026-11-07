require "test_helper"

# End to end: a real site bundle, `bin/studio install` through bundle exec,
# and the resulting bin/studio run from outside the site.
class Studio::SiteBintools::BinstubTest < Minitest::Test
  include SiteHelper

  def test_install_then_bin_studio_runs_the_gem_s_script_from_the_site_root
    gem_path = File.expand_path("../../..", __dir__)
    site_file "Gemfile", %(source "https://rubygems.org"\ngem "studio-site-bintools", path: "#{gem_path}"\n)
    fake "mise", 'echo "pwd $PWD" >> calls.log'

    output, status = Bundler.with_unbundled_env do
      system("bundle install --local --quiet", chdir: @site, exception: true)
      Open3.capture2e("bundle exec studio install", chdir: @site)
    end
    assert status.success?, output
    assert File.executable?(File.join(@site, "bin/setup"))

    output, status = Bundler.with_unbundled_env do
      Open3.capture2e({"PATH" => "#{@fakes}:#{ENV["PATH"]}"}, File.join(@site, "bin/studio"), "lint", chdir: "/")
    end

    assert status.success?, output
    assert_includes calls, "pwd #{@site}"
  end
end
