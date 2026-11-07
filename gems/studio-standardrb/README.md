# studio-standardrb

The studio's Ruby lint stack as one [Standard](https://github.com/standardrb/standard) plugin: Standard, standard-rails, rubocop-factory_bot, rubocop-rake, and the studio's own `Studio/*` cops.

## Setup

In the toolshed `git` block of the Gemfile:

    gem "studio-standardrb", group: [:development, :test], require: false

Don't also list `standard`, `standard-rails`, `rubocop-factory_bot` or `rubocop-rake`: they come with this gem. Pin one only when you need a specific version (`gem "standard", "1.56.0"`). Dependabot no longer bumps them; `bundle update studio-standardrb` does.

`.standard.yml` (Standard can't share it between repos, so each app keeps one):

    ignore:
      - "db/schema.rb":
        - Rails/CreateTableWithTimestamps

    plugins:
      - studio-standardrb
      - standard-rails
      - rubocop-factory_bot
      - rubocop-rake

`studio-standardrb` goes first: Standard plugins are first in wins.

An app that doesn't pass yet: `bundle exec standardrb --fix`, then `bundle exec standardrb --generate-todo` and commit `.standard_todo.yml`.

## Rules

Standard pins many built-in RuboCop cops to off and does not let a plugin switch them on. Where a rule below says "inherits", it is the built-in cop under a name Standard does not own.

### Studio/ClassStructure

Inherits `Layout/ClassStructure`. Class contents go in this order:

1. `include`, `extend`, `prepend`
2. Constants
3. Attribute macros: `attribute`, `enum`, `store_accessor`
4. Associations
5. Validations
6. Callbacks
7. Class methods
8. `initialize`
9. Public methods
10. Protected methods
11. Private methods

Macros not named in `config/base.yml` (`scope`, `normalizes`, `delegate`, `generates_token_for`, `attr_reader` and so on) are not checked, so they can sit where they read best.

Autocorrect is unsafe. It moves lines but drops the blank lines between groups, and the order of callbacks can change behaviour, so read the diff.

### Studio/ClassMethodsDefinitions

Inherits `Style/ClassMethodsDefinitions`. Class methods go inside `class << self`, never `def self.name`, even when there is only one. `private` works inside the block; above a `def self.` it does nothing. No autocorrect.

### Studio/NoUnless

Use `if !` instead of `unless`. Autocorrects, wrapping compound conditions in parentheses: `unless a && b` becomes `if !(a && b)`. An `unless` with an `else` is flagged but left for Standard's own `Style/UnlessElse` to rewrite first.

### Studio/WordArray and Studio/SymbolArray

Inherit `Style/WordArray` and `Style/SymbolArray` with the `brackets` style. Write `["a", "b"]` and `[:a, :b]`, not `%w[a b]` and `%i[a b]`. Autocorrects.
