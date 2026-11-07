require "test_helper"

class Studio::SiteBintoolsTest < Minitest::Test
  include SiteHelper

  def test_cli_replaces_the_process_with_the_named_script_run_from_the_site_root
    Kernel.expects(:exec).with(File.join(Studio::SiteBintools::LIBEXEC, "lint"), "--x", chdir: @site)

    Studio::SiteBintools.cli ["lint", "--x"], root: @site
  end

  def test_cli_with_no_script_lists_every_script_with_its_summary
    out = StringIO.new

    Studio::SiteBintools.cli [], root: @site, out: out

    assert_match "Usage: bin/studio <script> [args]", out.string
    assert_match(/^  ci +Lint, audit, check images, then build the site for production$/, out.string)
    assert_match(/^  install +Add bin\/studio and copy bin\/setup/, out.string)
  end

  def test_cli_rejects_unknown_scripts_with_the_list_and_a_failing_exit
    Kernel.expects(:exec).never

    _, err = capture_io do
      assert_equal 1, Studio::SiteBintools.cli(["bridgetown"], root: @site)
    end

    assert_match "unknown script: bridgetown", err
    assert_match "optimize-images", err
  end

  def test_install_copies_setup_once_and_adds_the_binstub
    Studio::SiteBintools.expects(:system).with("bundle binstubs studio-site-bintools", chdir: @site, exception: true).twice
    out = StringIO.new

    Studio::SiteBintools.cli ["install"], root: @site, out: out
    File.write(File.join(@site, "bin/setup"), "custom\n")
    Studio::SiteBintools.cli ["install"], root: @site, out: out

    assert_equal "custom\n", File.read(File.join(@site, "bin/setup"))
    assert_match "create  bin/setup", out.string
    assert_match "skip    bin/setup (site owns it)", out.string
  end

  def test_every_script_has_a_summary_is_executable_valid_and_finds_the_site_through_its_cwd
    Studio::SiteBintools.summaries.each do |script, summary|
      path = File.join(Studio::SiteBintools::LIBEXEC, script)
      source = File.read(path)

      refute_empty summary.to_s
      assert File.executable?(path), "#{script} is not executable"
      refute_match(/__dir__|dirname "\$0"/, source, "#{script} resolves paths from the gem, not the site")
      if source.start_with?("#!/usr/bin/env ruby")
        _, status = Open3.capture2e("ruby", "-c", path)
        assert status.success?, "#{script} has a syntax error"
      end
    end
  end
end
