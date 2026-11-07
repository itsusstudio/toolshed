require "test_helper"

class Studio::EnumTest < Minitest::Test
  MaterialTypes = Enums::Projects::MaterialTypes
  StripeEvents = Enums::Subscriptions::StripeEvents

  def test_each_value_becomes_a_frozen_constant
    assert_equal "gold", MaterialTypes::GOLD
    assert_equal "sterling_silver", MaterialTypes::STERLING_SILVER
    assert_predicate MaterialTypes::GOLD, :frozen?
  end

  def test_a_stored_value_can_differ_from_its_name
    assert_equal "invoice.paid", StripeEvents::INVOICE_PAID
    assert_equal :invoice_paid, StripeEvents.key_for("invoice.paid")
  end

  def test_values_and_keys_keep_declaration_order
    assert_equal ["gold", "sterling_silver"], MaterialTypes.values
    assert_equal [:gold, :sterling_silver], MaterialTypes.keys
  end

  def test_to_h_maps_names_to_stored_values
    assert_equal({invoice_paid: "invoice.paid"}, StripeEvents.to_h)
  end

  def test_lookups
    assert MaterialTypes.include?("gold")
    refute MaterialTypes.include?("tin")
    assert_equal "gold", MaterialTypes[:gold]
    assert_equal "gold", MaterialTypes["gold"]
    assert_nil MaterialTypes[:tin]
    assert_nil MaterialTypes.key_for("tin")
    assert_raises(KeyError) { MaterialTypes.fetch(:tin) }
  end

  def test_enumerates_its_values
    assert_equal ["GOLD", "STERLING_SILVER"], MaterialTypes.map(&:upcase)
  end

  def test_label_translates_under_the_class_path_and_falls_back_to_humanized
    assert_equal "Gold", MaterialTypes.label("gold")
    assert_equal "Sterling silver", MaterialTypes.label("sterling_silver")
    assert_equal "Invoice paid", StripeEvents.label("invoice.paid")
  end

  def test_options_pair_labels_with_values_for_a_select
    assert_equal [["Gold", "gold"], ["Sterling silver", "sterling_silver"]], MaterialTypes.options
  end

  def test_rejects_duplicate_and_malformed_names
    assert_raises(Studio::Enum::DuplicateValueError) do
      Class.new(Studio::Enum) do
        value :gold
        value :gold
      end
    end
    ["", "Gold", "two words", "1st"].each do |name|
      assert_raises(Studio::Enum::InvalidValueError) { Class.new(Studio::Enum) { value name } }
    end
  end

  def test_each_subclass_has_its_own_values
    assert_equal ["invoice.paid"], StripeEvents.values
    refute StripeEvents.include?("gold")
  end
end
