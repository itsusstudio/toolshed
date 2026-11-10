require "test_helper"

class Studio::Auth::DeliverabilityTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  Deliverability = Studio::Auth::Deliverability

  test "refuses addresses that can't receive mail without asking DNS" do
    ValidEmail2::Address.any_instance.expects(:valid_mx?).never

    ["name@gmail", "cook@example.com", "cook@studio.test", "cook@mailinator.com", "not an email"].each do |address|
      assert Deliverability.undeliverable?(address), address
    end
    refute Deliverability.undeliverable?("cook@studio.com")
  end

  test "a domain with no mail servers is caught in production only, with a short DNS timeout" do
    ValidEmail2::Address.any_instance.stubs(:valid_mx?).returns(false)
    refute Deliverability.domain_cannot_receive_mail?("cook@studio.com")

    Rails.env.stubs(:production?).returns(true)
    ValidEmail2::Dns.expects(:new).with(Deliverability::DNS_TIMEOUT).returns(Object.new)
    assert Deliverability.domain_cannot_receive_mail?("cook@studio.com")
  end

  test "the mail job drops a message the provider refuses instead of retrying" do
    stub_const_resend
    user = User.create!(email_address: "cook@studio.com")
    Studio::Auth::SignInMailer.any_instance.expects(:deliver_to).once.raises(Resend::Error::InvalidRequestError, "Invalid `to` field")

    assert_nothing_raised do
      perform_enqueued_jobs { Studio::Auth::SignInMailer.with(user: user).locked.deliver_later }
    end
    assert_enqueued_jobs 0
  end

  private

  def stub_const_resend
    return if defined?(::Resend::Error::InvalidRequestError)

    Object.const_set(:Resend, Module.new)
    Resend.const_set(:Error, Module.new)
    Resend::Error.const_set(:InvalidRequestError, Class.new(StandardError))
  end
end
