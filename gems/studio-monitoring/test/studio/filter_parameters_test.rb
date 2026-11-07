require "test_helper"

class Studio::Monitoring::FilterParametersTest < ActiveSupport::TestCase
  FILTER = ActiveSupport::ParameterFilter.new(Studio::Monitoring::FILTER_PARAMETERS)

  FILTERED = [
    "password", "password_confirmation", "password_digest", "client_secret", "api_key", "private_key", "encoded_key", "variation_key", "token", "access_token", "refresh_token", "id_token", "auth_token", "session_token", "reset_token", "_csrf_token", "Authorization", "code", "verification_code", "state", "session_id", "signed_blob_id", "signature", "x_goog_signature", "cookie", "otp_attempt", "email", "email_address", "phone_number", "ip_address", "address", "zip_code", "date_of_birth", "ssn", "passport", "cvv", "credit_card_number", "account_number"
  ].freeze

  KEPT = [
    "input_tokens", "output_tokens", "cache_read_tokens", "cache_write_tokens", "tokens_used", "error_code", "status_code", "country_code", "currency_code", "analytics_session_id", "statement", "status", "estate", "client_id", "recipe_id", "actor_id", "tenant_id", "event_name", "content_type", "disposition"
  ].freeze

  test "filters credentials, personal and payment data" do
    unfiltered = FILTERED.reject { |key| FILTER.filter(key => "x")[key] == "[FILTERED]" }

    assert_empty unfiltered
  end

  test "keeps counts, codes and ids that only contain a sensitive word" do
    filtered = KEPT.select { |key| FILTER.filter(key => "x")[key] == "[FILTERED]" }

    assert_empty filtered
  end
end
