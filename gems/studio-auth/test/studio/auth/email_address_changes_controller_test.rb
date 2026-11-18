require "test_helper"

class Studio::Auth::EmailAddressChangesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include AuthenticationTestHelpers

  test "changing the email address requires authentication" do
    get change_email_address_path
    assert_redirected_to login_path

    post change_email_address_path, params: {email_address: "new@studio.com"}
    assert_redirected_to login_path
  end

  test "a fresh sign-in sends one code to the new address, then changes it and tells the old one" do
    perform_enqueued_jobs { sign_in_with_code("cook@studio.com") }

    request_change("New@Studio.com ")
    code_mail = last_mail_to("new@studio.com")
    assert_includes code_mail.subject, code_in(code_mail)
    assert_nil last_mail_to("cook@studio.com", after: code_mail)

    perform_enqueued_jobs { post verify_email_address_change_path, params: {code: code_in(code_mail)} }

    assert_redirected_to root_path
    assert_equal "new@studio.com", User.first.email_address
    assert_not_nil last_mail_to("cook@studio.com", after: code_mail)
    get "/private"
    assert_response :success
  end

  test "an older session proves the current address before the new one gets a code" do
    perform_enqueued_jobs { sign_in_with_code("cook@studio.com") }
    travel 1.hour

    request_change("new@studio.com")
    assert_nil last_mail_to("new@studio.com")
    current_code = code_in(last_mail_to("cook@studio.com"))

    perform_enqueued_jobs { post verify_email_address_change_path, params: {code: current_code} }
    assert_redirected_to verify_email_address_change_path
    assert_equal "cook@studio.com", User.first.email_address

    perform_enqueued_jobs { post verify_email_address_change_path, params: {code: code_in(last_mail_to("new@studio.com"))} }
    assert_equal "new@studio.com", User.first.email_address
  end

  test "a wrong code changes nothing" do
    perform_enqueued_jobs { sign_in_with_code("cook@studio.com") }
    request_change("new@studio.com")

    post verify_email_address_change_path, params: {code: "000000"}

    assert_response :unprocessable_content
    assert_select "#code-error"
    assert_equal "cook@studio.com", User.first.email_address
  end

  test "an address another account uses, or the same address, is refused before any code" do
    perform_enqueued_jobs { sign_in_with_code("cook@studio.com") }
    create_authentication_user("taken@studio.com")
    mails = ActionMailer::Base.deliveries.size

    ["Taken@studio.com", "cook@studio.com", "not-an-address"].each do |email_address|
      request_change(email_address)

      assert_response :unprocessable_content
      assert_select "input[name=email_address][aria-invalid=true]"
    end
    assert_equal mails, ActionMailer::Base.deliveries.size
  end

  test "the address is checked again when the code comes back" do
    perform_enqueued_jobs { sign_in_with_code("cook@studio.com") }
    request_change("new@studio.com")
    code = code_in(last_mail_to("new@studio.com"))
    create_authentication_user("new@studio.com")

    post verify_email_address_change_path, params: {code: code}

    assert_redirected_to change_email_address_path
    assert_equal "cook@studio.com", User.find_by(email_address: "cook@studio.com").email_address
  end

  test "changing the address ends a pending sign-up for the new one" do
    perform_enqueued_jobs { sign_in_with_code("cook@studio.com") }
    Studio::Auth::PendingSignUp.record!(email_address: "new@studio.com", full_name: "New Cook")
    request_change("new@studio.com")

    perform_enqueued_jobs { post verify_email_address_change_path, params: {code: code_in(last_mail_to("new@studio.com"))} }

    assert_not Studio::Auth::PendingSignUp.exists?(email_address: "new@studio.com")
  end

  test "the code page needs a change in progress" do
    perform_enqueued_jobs { sign_in_with_code("cook@studio.com") }

    get verify_email_address_change_path

    assert_redirected_to change_email_address_path
  end

  private

  def request_authentication_code(email_address)
    ActionMailer::Base.deliveries.clear
    perform_enqueued_jobs { post login_path, params: {email_address: email_address} }
    code_in(ActionMailer::Base.deliveries.last)
  end

  def request_change(email_address)
    perform_enqueued_jobs { post change_email_address_path, params: {email_address: email_address} }
  end

  def last_mail_to(email_address, after: nil)
    deliveries = ActionMailer::Base.deliveries
    deliveries = deliveries.drop(deliveries.index(after) + 1) if after
    deliveries.rfind { it.to.include?(email_address) }
  end

  def code_in(mail)
    mail.text_part.body.to_s[/\b\d{6}\b/]
  end
end
