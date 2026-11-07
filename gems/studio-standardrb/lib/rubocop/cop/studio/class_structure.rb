module RuboCop
  module Cop
    module Studio
      # Standard pins Layout/ClassStructure to off and will not let a plugin
      # change it, so the same check ships here under a name Standard does not own.
      class ClassStructure < RuboCop::Cop::Layout::ClassStructure
      end
    end
  end
end
