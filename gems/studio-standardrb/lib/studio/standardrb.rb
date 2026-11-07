require "lint_roller"
require "rubocop"

module Studio
  module Standardrb
    VERSION = File.read(File.expand_path("../../../../VERSION", __dir__)).strip
  end
end

require_relative "../rubocop/cop/studio/class_methods_definitions"
require_relative "../rubocop/cop/studio/class_structure"
require_relative "../rubocop/cop/studio/no_unless"
require_relative "../rubocop/cop/studio/symbol_array"
require_relative "../rubocop/cop/studio/word_array"
require_relative "standardrb/plugin"
