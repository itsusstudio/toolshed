module RuboCop
  module Cop
    module Studio
      class NoUnless < Base
        extend AutoCorrector

        MSG = "Use `if !` instead of `unless`."
        BARE_NEGATABLE_TYPES = [:lvar, :ivar, :cvar, :gvar, :const, :begin, :defined?, :csend].freeze

        def on_if(node)
          return if !node.unless?

          add_offense(node.loc.keyword) do |corrector|
            next if node.else?

            corrector.replace(node.loc.keyword, "if")
            corrector.replace(node.condition, negated(node.condition))
          end
        end

        private

        def negated(condition)
          return condition.receiver.source if negation?(condition)
          return "!#{condition.source}" if bare_negatable?(condition)

          "!(#{condition.source})"
        end

        def negation?(condition)
          condition.send_type? && condition.method?(:!)
        end

        def bare_negatable?(condition)
          return true if BARE_NEGATABLE_TYPES.include?(condition.type)

          condition.send_type? && !condition.operator_method? && (condition.arguments.empty? || condition.parenthesized?)
        end
      end
    end
  end
end
