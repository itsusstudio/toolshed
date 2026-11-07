require "test_helper"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table(:materials) { |t| t.string :material_type }
end

class Material < ActiveRecord::Base # standard:disable Rails/ApplicationRecord -- a bare test model, no app
  enum :material_type, Enums::Projects::MaterialTypes.to_h, default: :gold, validate: true
end

class Studio::RailsEnumTest < Minitest::Test
  def test_to_h_drives_a_rails_enum_column
    material = Material.create!(material_type: Enums::Projects::MaterialTypes::STERLING_SILVER)

    assert_predicate material, :sterling_silver?
    assert_equal "sterling_silver", material.reload.material_type
    assert_equal "gold", Material.new.material_type
    assert_equal [material], Material.sterling_silver.to_a
  end

  def test_rails_rejects_values_outside_the_enum
    refute_predicate Material.new(material_type: "tin"), :valid?
  end
end
