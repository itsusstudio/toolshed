require "test_helper"

class Studio::Billing::CatalogTest < StudioBillingTestCase
  def test_unit_amounts_convert_each_currency_to_cents
    assert_equal({"cad" => 59_000, "usd" => 43_000}, catalog.find_price("team_yearly").unit_amounts)
    assert_equal({"cad" => 6_900}, catalog.find_price("team_monthly").unit_amounts)
  end

  def test_unit_amounts_follow_each_currency_minor_unit
    data = CATALOG.deep_dup
    data["plans"][1]["prices"][0]["amounts"]["JPY"] = 5900

    assert_equal 5_900, catalog(data).find_price("team_yearly").unit_amounts.fetch("jpy")
  end

  def test_amount_returns_money_in_that_currency
    amount = catalog.find_price("team_yearly").amount(:USD)

    assert_equal Money.from_amount(430, "USD"), amount
  end

  def test_initialize_raises_on_an_unknown_currency
    data = CATALOG.deep_dup
    data["plans"][1]["prices"][0]["amounts"]["XYZ"] = 10

    assert_raises(Studio::Billing::Catalog::Error) { catalog(data) }
  end

  def test_initialize_raises_on_more_decimal_places_than_the_currency_allows
    data = CATALOG.deep_dup
    data["plans"][1]["prices"][0]["amounts"]["CAD"] = "590.005"

    assert_raises(Studio::Billing::Catalog::Error) { catalog(data) }
  end

  def test_free_is_true_only_for_a_plan_without_prices
    assert_predicate catalog.find_plan("free"), :free?
    refute_predicate catalog.find_plan("team"), :free?
  end

  def test_checkout_branding_settings_maps_urls_to_stripe_images
    settings = catalog.checkout_branding_settings

    assert_equal "Workbench", settings[:display_name]
    assert_equal "rounded", settings[:border_style]
    assert_equal({type: "url", url: "https://useworkbench.co/icon.png"}, settings[:icon])
    assert_nil settings[:logo]
  end

  def test_initialize_raises_without_branding
    data = CATALOG.deep_dup
    data.delete("branding")

    error = assert_raises(Studio::Billing::Catalog::Error) { catalog(data) }
    assert_match "display_name", error.message
  end

  def test_initialize_raises_on_a_colour_that_is_not_hex
    data = CATALOG.deep_dup
    data["branding"]["button_color"] = "black"

    assert_raises(Studio::Billing::Catalog::Error) { catalog(data) }
  end

  def test_initialize_raises_on_an_unknown_branding_key
    data = CATALOG.deep_dup
    data["branding"]["accent_color"] = "#000000"

    assert_raises(Studio::Billing::Catalog::Error) { catalog(data) }
  end

  def test_initialize_raises_on_an_icon_url_that_is_not_https
    data = CATALOG.deep_dup
    data["branding"]["icon_url"] = "http://useworkbench.co/icon.png"

    assert_raises(Studio::Billing::Catalog::Error) { catalog(data) }
  end

  def test_base_currency_is_the_first_amount_listed
    assert_equal "cad", catalog.find_price("team_yearly").base_currency
  end

  def test_initialize_raises_on_a_repeated_lookup_key
    data = CATALOG.deep_dup
    data["plans"][2]["prices"][0]["lookup_key"] = "team_yearly"

    error = assert_raises(Studio::Billing::Catalog::Error) { catalog(data) }
    assert_match "team_yearly", error.message
  end

  def test_initialize_raises_on_an_unknown_interval
    data = CATALOG.deep_dup
    data["plans"][1]["prices"][0]["interval"] = "week"

    assert_raises(Studio::Billing::Catalog::Error) { catalog(data) }
  end

  def test_initialize_raises_on_a_price_without_amounts
    data = CATALOG.deep_dup
    data["plans"][1]["prices"][0].delete("amounts")

    assert_raises(Studio::Billing::Catalog::Error) { catalog(data) }
  end

  def test_unlimited_reads_as_nil_and_numbers_stay_numbers
    limits = catalog.find_plan("team").limits

    assert_nil limits.fetch("locations")
    assert_equal 250, limits.fetch("texts")
  end

  def test_feature_and_limit_names_cover_every_plan
    assert_equal ["texts", "remove_branding"], catalog.feature_names
    assert_equal ["new_jobs", "texts", "locations"], catalog.limit_names
  end

  def test_initialize_raises_when_a_plan_leaves_out_a_limit
    data = CATALOG.deep_dup
    data["plans"][0]["limits"].delete("locations")

    error = assert_raises(Studio::Billing::Catalog::Error) { catalog(data) }
    assert_match "locations", error.message
  end

  def test_initialize_raises_on_entitlements_of_an_unknown_plan
    data = CATALOG.deep_dup
    data["plans"][2]["entitlements_of"] = "pro"

    assert_raises(Studio::Billing::Catalog::Error) { catalog(data) }
  end

  def test_initialize_raises_when_a_plan_with_entitlements_of_sets_its_own_limits
    data = CATALOG.deep_dup
    data["plans"][2]["limits"] = {"new_jobs" => 5, "texts" => 0, "locations" => 1}

    assert_raises(Studio::Billing::Catalog::Error) { catalog(data) }
  end

  def test_initialize_raises_on_a_limit_that_is_not_a_whole_number_or_unlimited
    data = CATALOG.deep_dup
    data["plans"][1]["limits"]["texts"] = "lots"

    assert_raises(Studio::Billing::Catalog::Error) { catalog(data) }
  end
end
