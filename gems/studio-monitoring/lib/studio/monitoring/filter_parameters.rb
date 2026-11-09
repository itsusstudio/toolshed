module Studio
  module Monitoring
    # Symbols match anywhere in a key, case-insensitively (:passw catches
    # password_confirmation). Words that also appear inside harmless keys are
    # anchored Regexps instead, so input_tokens, error_code and
    # analytics_session_id stay readable.
    FILTER_PARAMETERS = [
      # Credentials and secrets
      :passw, :secret, :_key, :crypt, :salt, :certificate, :otp, :bearer, :authorization, :hmac,
      :signature, :cookie,
      /token\z/i,
      /\A(code|auth_code|authorization_code|verification_code)\z/i,
      /\Astate\z/i,
      /\Asession_id\z/i,
      :signed_blob_id,

      # Personal data. Bare "name" stays readable: apps use it for things
      # (recipes, templates), not people.
      :full_name, :first_name, :last_name, :given_name, :family_name, :surname,
      :email, :phone, :ip_address, :remote_ip, :address, :zip_code, :postal_code,
      :date_of_birth, :dob, :ssn, :social_security_number, :passport, :license_number, :drivers_license,

      # Payment
      :cvv, :cvc, :credit_card_number, :routing_number, :account_number, :bank_account
    ].freeze
  end
end
