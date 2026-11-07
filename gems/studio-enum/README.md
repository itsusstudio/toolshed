# studio-enum

Named string values for studio Rails apps: one class per enum, with constants, lookups, a Rails `enum` mapping and translated labels.

```ruby
module Enums
  module Projects
    class Statuses < Studio::Enum
      value :active
      value :archived
    end
  end
end

module Enums
  module Subscriptions
    class StripeEvents < Studio::Enum
      value :invoice_paid, "invoice.paid"   # stored value differs from the name
    end
  end
end
```

```ruby
Enums::Projects::Statuses::ACTIVE              # => "active"
Enums::Projects::Statuses.values               # => ["active", "archived"]
Enums::Projects::Statuses.include?("active")   # => true
Enums::Projects::Statuses.fetch(:active)       # => "active"; KeyError on a typo ([] returns nil)
Enums::Projects::Statuses.key_for("active")    # => :active
Enums::Projects::Statuses.to_h                 # => {active: "active", archived: "archived"}
```

Enums are Enumerable over their values (`map`, `each`, `to_a`).

## Models

```ruby
enum :status, Enums::Projects::Statuses.to_h, default: :active, validate: true
validates :occasion, inclusion: {in: Enums::Projects::Occasions.values}, allow_nil: true
```

## Labels

`label` translates by name under `enums.<class path>`, without the app's `Enums` prefix, and falls back to the humanized name:

```yaml
en:
  enums:
    projects:
      material_types:
        gold: Gold
```

```ruby
Enums::Projects::MaterialTypes.label("gold")             # => "Gold"
f.select :material_type, Enums::Projects::MaterialTypes.options   # => [["Gold", "gold"], ...]
```

## Rules

Names are lowercase snake_case and unique per enum; anything else raises at class load. Values keep declaration order. Logic specific to one enum (`category_for`, `non_owners`) goes in a `class << self` block on that enum.

## Setup

In the toolshed `git` block of the Gemfile: `gem "studio-enum"`.
