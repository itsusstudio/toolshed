require "test_helper"

class Studio::Billing::SyncTest < StudioBillingTestCase
  def test_changes_notes_an_active_price_on_a_gem_product_without_a_catalog_lookup_key
    stub_matching_account
    stub_product_prices("team",
      stripe_price("price_ty", "team_yearly", "team", "year", cad: 59_000),
      stripe_price("price_orphan", nil, "team", "year", cad: 50_000))

    note = sync.changes.find { it.subject == "price price_orphan" }
    assert_equal :note, note.action
    assert_predicate sync, :in_sync?
  end

  def test_changes_on_a_fresh_account_create_everything
    stub_fresh_account

    actions = sync.changes.map { [it.action, it.subject] }

    assert_equal [
      [:create, "product team"],
      [:create, "product simple"],
      [:create, "price team_yearly"],
      [:create, "price team_monthly"],
      [:create, "price simple_yearly"],
      [:update, "customer portal bpc_test"],
      [:create, "webhook endpoint"]
    ], actions
  end

  def test_apply_on_a_fresh_account_creates_multi_currency_prices_and_returns_the_webhook_secret
    stub_fresh_account
    Studio::Billing::Prices.stubs(:id_for).returns("price_new")
    client.v1.products.stubs(:create)
    client.v1.prices.stubs(:create)
    client.v1.billing_portal.configurations.stubs(:update)

    client.v1.prices.expects(:create).with do |params|
      params[:lookup_key] == "team_yearly" &&
        params[:currency] == "cad" && params[:unit_amount] == 59_000 &&
        params[:currency_options] == {"usd" => {unit_amount: 43_000, tax_behavior: "inclusive"}} &&
        params[:transfer_lookup_key] == false
    end
    client.v1.webhook_endpoints.expects(:create)
      .with { it[:url] == WEBHOOK_URL && it[:api_version] == API_VERSION }
      .returns(stripe_object(id: "we_1", secret: "whsec_new"))

    result = sync.apply!

    assert_equal "whsec_new", result.webhook_secret
  end

  def test_portal_without_a_configuration_id_is_a_by_hand_step_that_blocks_in_sync
    stub_matching_account
    Studio::Billing.config.portal_configuration_id = nil
    client.v1.billing_portal.configurations.expects(:update).never

    change = sync.changes.find { it.subject == "customer portal" }
    assert_equal :by_hand, change.action
    refute_predicate sync, :in_sync?
    sync.apply!
  end

  def test_a_new_price_id_behind_the_same_lookup_key_updates_the_portal
    stub_matching_account
    Studio::Billing::Prices.stubs(:id_for).returns("price_moved")

    assert_equal :update, sync.changes.find { it.subject == "customer portal bpc_test" }.action
  end

  def test_fresh_account_doesnt_list_prices_for_products_that_dont_exist_yet
    stub_fresh_account
    client.v1.prices.expects(:list).with { it.key?(:product) }.never

    sync.changes
  end

  def test_portal_settings_changed_in_the_dashboard_are_drift
    stub_matching_account
    live = sync.send(:portal_params).deep_dup
    live[:features][:subscription_cancel][:enabled] = false
    stub_live_portal(live)

    assert_equal :update, sync.changes.find { it.subject == "customer portal bpc_test" }.action
  end

  def test_a_price_with_a_different_tax_behavior_is_replaced
    stub_matching_account
    stub_price("team_monthly",
      stripe_price("price_tm", "team_monthly", "team", "month", tax_behavior: "unspecified", cad: 6_900))

    assert_equal :replace, sync.changes.find { it.subject == "price team_monthly" }.action
  end

  def test_in_sync_is_true_when_stripe_matches_the_catalog
    stub_matching_account

    assert_predicate sync, :in_sync?
  end

  def test_apply_when_in_sync_changes_nothing
    stub_matching_account
    client.v1.products.expects(:update).never
    client.v1.prices.expects(:create).never
    client.v1.prices.expects(:update).never

    sync.apply!
  end

  def test_a_changed_amount_replaces_the_price_and_archives_the_old_one
    stub_matching_account
    stub_price("team_yearly", stripe_price("price_old", "team_yearly", "team", "year", cad: 50_000, usd: 43_000))

    change = sync.changes.find { it.subject == "price team_yearly" }
    assert_equal :replace, change.action

    client.v1.prices.expects(:create).with { it[:lookup_key] == "team_yearly" && it[:transfer_lookup_key] }
    client.v1.prices.expects(:update).with("price_old", {active: false})
    Studio::Billing::Prices.stubs(:id_for).returns("price_new")
    client.v1.billing_portal.configurations.expects(:update).with do |id, params|
      id == "bpc_test" && params.dig(:features, :subscription_update, :products).first[:prices].include?("price_new")
    end

    sync.apply!
  end

  def test_an_added_currency_replaces_the_price
    stub_matching_account
    stub_price("team_yearly", stripe_price("price_old", "team_yearly", "team", "year", cad: 59_000))

    assert_equal :replace, sync.changes.find { it.subject == "price team_yearly" }.action
  end

  def test_a_legacy_price_on_another_product_is_left_alone
    stub_matching_account
    stub_price("simple_yearly", stripe_price("price_s", "simple_yearly", "prod_old", "year", cad: 34_800))

    assert_nil sync.changes.find { it.subject == "price simple_yearly" }
  end

  def test_a_current_price_on_another_product_is_only_noted
    stub_matching_account
    stub_price("team_monthly", stripe_price("price_tm", "team_monthly", "prod_old", "month", cad: 6_900))

    change = sync.changes.find { it.subject == "price team_monthly" }
    assert_equal :note, change.action
    assert_predicate sync, :in_sync?
  end

  def test_webhook_events_that_differ_are_updated
    stub_matching_account
    client.v1.webhook_endpoints.stubs(:list).returns(stripe_list(
      stripe_object(id: "we_1", url: WEBHOOK_URL, enabled_events: ["invoice.paid"], api_version: API_VERSION)
    ))

    change = sync.changes.find { it.subject == "webhook endpoint" }
    assert_equal :update, change.action
  end

  def test_a_product_with_a_different_name_is_updated
    stub_matching_account
    client.v1.products.stubs(:retrieve).with("team").returns(stripe_product("team", "Team",
      description: "For independent shops"))

    change = sync.changes.find { it.subject == "product team" }
    assert_equal :update, change.action
    assert_equal "name", change.detail
  end

  private

  def sync
    @sync ||= Studio::Billing::Sync.new(catalog: catalog, config: Studio::Billing.config, client: client)
  end

  def stub_fresh_account
    client.v1.products.stubs(:retrieve).raises(resource_missing)
    client.v1.prices.stubs(:list).returns(stripe_list)
    client.v1.billing_portal.configurations.stubs(:retrieve).with("bpc_test")
      .returns(stripe_object(id: "bpc_test", metadata: {}))
    client.v1.webhook_endpoints.stubs(:list).returns(stripe_list)
  end

  def stub_matching_account
    client.v1.products.stubs(:retrieve).with("team").returns(stripe_product("team", "Workbench Team",
      description: "For independent shops"))
    client.v1.products.stubs(:retrieve).with("simple").returns(stripe_product("simple", "Workbench Simple"))

    stub_price("team_yearly", stripe_price("price_ty", "team_yearly", "team", "year", cad: 59_000, usd: 43_000))
    stub_price("team_monthly", stripe_price("price_tm", "team_monthly", "team", "month", cad: 6_900))
    stub_price("simple_yearly", stripe_price("price_sy", "simple_yearly", "simple", "year", cad: 34_800))
    stub_product_prices("team", stripe_price("price_ty", "team_yearly", "team", "year", cad: 59_000))
    stub_product_prices("simple", stripe_price("price_sy", "simple_yearly", "simple", "year", cad: 34_800))

    Studio::Billing::Prices.stubs(:id_for).returns("price_x")
    stub_live_portal(sync.send(:portal_params))

    client.v1.webhook_endpoints.stubs(:list).returns(stripe_list(
      stripe_object(id: "we_1", url: WEBHOOK_URL, enabled_events: Studio::Billing.config.webhook_events,
        api_version: API_VERSION)
    ))
  end

  def stub_live_portal(settings)
    client.v1.billing_portal.configurations.stubs(:retrieve).with("bpc_test")
      .returns(stripe_object({id: "bpc_test", object: "billing_portal.configuration"}.merge(settings)))
  end

  def stub_product_prices(product, *prices)
    client.v1.prices.stubs(:list).with { it[:product] == product }.returns(stripe_list(*prices))
  end

  def stub_price(lookup_key, price)
    client.v1.prices.stubs(:list).with { it[:lookup_keys] == [lookup_key] }.returns(stripe_list(price))
  end

  def stripe_product(id, name, description: nil)
    stripe_object({id: id, object: "product", name: name, description: description,
                   tax_code: "txcd_10103001", active: true}.compact)
  end

  def stripe_price(id, lookup_key, product, interval, tax_behavior: "inclusive", **unit_amounts)
    base_currency, base_amount = unit_amounts.first
    stripe_object(
      id: id, object: "price", lookup_key: lookup_key, product: product, active: true,
      currency: base_currency.to_s, unit_amount: base_amount, recurring: {interval: interval},
      tax_behavior: tax_behavior,
      currency_options: unit_amounts.to_h do |currency, amount|
        [currency, {unit_amount: amount, tax_behavior: tax_behavior}]
      end
    )
  end
end
