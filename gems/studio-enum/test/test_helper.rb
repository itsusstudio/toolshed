require "studio/enum"
require "active_record"
require "minitest/autorun"

I18n.available_locales = [:en]
I18n.backend.store_translations(:en, enums: {projects: {material_types: {gold: "Gold"}}})

module Enums
  module Projects
    class MaterialTypes < Studio::Enum
      value :gold
      value :sterling_silver
    end
  end

  module Subscriptions
    class StripeEvents < Studio::Enum
      value :invoice_paid, "invoice.paid"
    end
  end
end
