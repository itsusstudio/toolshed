module Studio
  module Auth
    module Deliverability
      # RFC 2606 and RFC 6761 reserve these; mail to them never arrives.
      RESERVED_DOMAINS = ["example.com", "example.net", "example.org"].freeze
      RESERVED_TLDS = ["test", "example", "invalid", "localhost"].freeze
      DNS_TIMEOUT = 2

      class << self
        def undeliverable?(email_address)
          address = ValidEmail2::Address.new(email_address.to_s)
          !address.valid? || reserved?(email_address) || address.disposable_domain?
        end

        # For an address being saved, never at sign-in: a DNS timeout reads
        # the same as a dead domain. Production only, since development and
        # test addresses often have no mail servers and tests stay offline.
        def domain_cannot_receive_mail?(email_address)
          return false if !::Rails.env.production?

          !ValidEmail2::Address.new(email_address.to_s, ValidEmail2::Dns.new(DNS_TIMEOUT)).valid_mx?
        end

        private

        def reserved?(email_address)
          domain = email_address.to_s.split("@").last.to_s.downcase
          domain.in?(RESERVED_DOMAINS) || domain.split(".").last.in?(RESERVED_TLDS)
        end
      end
    end
  end
end
