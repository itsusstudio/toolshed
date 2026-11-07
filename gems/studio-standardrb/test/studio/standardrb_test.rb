require "test_helper"

class Studio::StandardrbTest < Minitest::Test
  include LintHelper

  def test_clean_code_passes
    assert_empty offenses(<<~RUBY)
      class Recipe
        class << self
          def find_all
            ["a", "b"] if !blank?
          end
        end
      end
    RUBY
  end

  def test_no_unless_rewrites_to_if_not
    assert_includes offenses("puts 1 unless ready?\n"), "Studio/NoUnless"
    assert_equal "puts 1 if !ready?\n", fixed("puts 1 unless ready?\n")
    assert_equal "puts 1 if !(a && b)\n", fixed("puts 1 unless a && b\n")
  end

  def test_word_and_symbol_arrays_use_brackets
    assert_includes offenses("puts %w[a b]\n"), "Studio/WordArray"
    assert_equal %(puts ["a", "b"]\n), fixed("puts %w[a b]\n")
    assert_equal "puts [:a, :b]\n", fixed("puts %i[a b]\n")
  end

  def test_class_methods_go_in_class_self
    assert_includes offenses(<<~RUBY), "Studio/ClassMethodsDefinitions"
      class Recipe
        def self.find_all
        end
      end
    RUBY
  end

  def test_class_structure_orders_associations_before_validations
    assert_includes offenses(<<~RUBY), "Studio/ClassStructure"
      class Recipe
        validates :name, presence: true
        has_many :steps
      end
    RUBY
  end
end
