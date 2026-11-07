require "test_helper"

# magick, cwebp and identify are fakes: cwebp writes its arguments as the
# "image", so the tests can see the encode settings and --check compares
# deterministic bytes.
class Studio::SiteBintools::OptimizeImagesTest < Minitest::Test
  include SiteHelper

  def setup
    super
    fake "magick", 'cat > /dev/null 2>&1 || true; echo "png"'
    fake "cwebp", <<~SH
      cat > /dev/null
      while [ "$#" -gt 0 ]; do [ "$1" = "-o" ] && out="$2"; shift; done
      cat "${0%/*}/../calls.log" | grep '^magick' | tail -1 > "$out"
    SH
    fake "identify", 'printf "10x10"'
    site_file "config/images.yml", <<~YAML
      default_max_width: 1600
      sources: [src/images]
      rules:
        - match: og-image.png
          skip: true
        - match: src/images/shots/*
          max_width: 1400
          max_height: 900
    YAML
    site_file "src/images/hero.png", "source"
    site_file "src/images/og-image.png", "source"
    site_file "src/images/shots/a.png", "source"
  end

  def test_encodes_each_source_to_webp_within_its_bounds_and_skips_by_config
    output, status = run_script("optimize-images")

    assert status.success?, output
    assert_match(/-resize 1600> /, File.read(File.join(@site, "src/images/hero.webp")))
    assert_match(/-resize 1400x900> /, File.read(File.join(@site, "src/images/shots/a.webp")))
    refute File.exist?(File.join(@site, "src/images/og-image.webp"))
    assert_match "2 images", output
    assert_match "1 skipped by config", output
  end

  def test_prune_deletes_sources_once_encoded
    run_script("optimize-images", "--prune")

    refute File.exist?(File.join(@site, "src/images/hero.png"))
    assert File.exist?(File.join(@site, "src/images/og-image.png"))
  end

  def test_check_passes_when_every_webp_is_up_to_date
    run_script("optimize-images")

    output, status = run_script("optimize-images", "--check")

    assert status.success?, output
    assert_match "2 images up to date", output
  end

  def test_check_lists_missing_webp_without_writing_any
    output, status = run_script("optimize-images", "--check")

    refute status.success?
    assert_match "src/images/hero.png", output
    refute File.exist?(File.join(@site, "src/images/hero.webp"))
  end

  def test_reports_when_everything_is_skipped
    output, status = run_script("optimize-images", File.join(@site, "src/images/og-image.png"))

    assert status.success?, output
    assert_match "1 skipped by config, nothing to encode", output
  end
end
