module Studio
  module Auth
    module Deliverability
      # RFC 2606 and RFC 6761 reserve these; mail to them never arrives.
      RESERVED_DOMAINS = ["example.com", "example.net", "example.org"].freeze
      RESERVED_TLDS = ["test", "example", "invalid", "localhost"].freeze
      PLACEHOLDER_DOMAINS = ["test.com", "email.com", "domain.com", "mailinator.com"].freeze

      class << self
        def undeliverable?(email_address)
          return true if !email_address.match?(URI::MailTo::EMAIL_REGEXP)

          domain = email_address.split("@").last
          domain.in?(RESERVED_DOMAINS) || domain.in?(PLACEHOLDER_DOMAINS) || domain.split(".").last.in?(RESERVED_TLDS)
        end
      end
    end
  end
end
