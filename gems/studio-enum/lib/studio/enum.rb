require "active_support"
require "active_support/core_ext/string/inflections"
require "i18n"

module Studio
  # One subclass per enum:
  #
  #   module Enums
  #     module Projects
  #       class Statuses < Studio::Enum
  #         value :active
  #         value :archived
  #       end
  #     end
  #   end
  class Enum
    class Error < StandardError; end
    class DuplicateValueError < Error; end
    class InvalidValueError < Error; end

    class << self
      include Enumerable

      def inherited(subclass)
        super
        subclass.instance_variable_set(:@entries, {})
      end

      # Defines NAME = "name", or NAME = stored when the stored value differs.
      def value(name, stored = name)
        key = name.to_s
        raise InvalidValueError, "#{self.name}: #{key.inspect} is not a lowercase snake_case name" if !key.match?(/\A[a-z][a-z0-9_]*\z/)
        raise DuplicateValueError, "#{self.name}: #{key} is already defined" if @entries.key?(key.to_sym)

        stored = stored.to_s.dup.freeze
        @entries[key.to_sym] = stored
        const_set(key.upcase, stored)
      end

      def values
        @entries.values.freeze
      end

      def keys
        @entries.keys.freeze
      end

      # Name to stored value, the hash Rails' enum takes:
      #   enum :status, Enums::Projects::Statuses.to_h, default: :active
      def to_h
        @entries.dup
      end

      def each(&)
        values.each(&)
      end

      def include?(value)
        @entries.value?(value)
      end

      def [](name)
        @entries[name.to_sym]
      end

      def fetch(name)
        @entries.fetch(name.to_sym)
      end

      def key_for(value)
        @entries.key(value)
      end

      # Translated under enums.<class path> by name: Enums::Projects::MaterialTypes
      # reads enums.projects.material_types.gold. By name, not stored value,
      # so a stored "invoice.paid" isn't read as a nested key. Falls back to
      # the humanized name.
      def label(value)
        name = key_for(value) || value.to_s
        I18n.t(name, scope: i18n_scope, default: name.to_s.humanize)
      end

      # [[label, value], ...] for a form select.
      def options
        values.map { [label(it), it] }
      end

      private

      def i18n_scope
        ["enums", *name.underscore.delete_prefix("enums/").split("/")]
      end
    end
  end
end
