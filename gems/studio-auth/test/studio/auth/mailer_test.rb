require "test_helper"

class Studio::Auth::MailerTest < ActionMailer::TestCase
  Mailer = Studio::Auth::Mailer

  setup do
    @user = User.create!(email_address: "cook@studio.com")
    @challenge = Studio::Auth::LoginChallenge.create!(
      user: @user, purpose: "sign_in", code_digest: "digest", expires_at: 10.minutes.from_now,
      ip_address: "1.2.3.4", user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15"
    )
  end

  test "login_code has text and HTML parts with the code in the subject and no links" do
    mail = login_code_mail.deliver_now

    assert_equal "123456 is your Dummy code", mail.subject
    assert_equal ["hello@dummy.app"], mail.from
    assert_equal "multipart/alternative", mail.mime_type
    [mail.text_part, mail.html_part].each do |part|
      assert_includes part.body.to_s, "123456"
      assert_includes part.body.to_s, "Safari on Mac"
      assert_no_match(%r{https?://|<a\b|<img\b}, part.body.to_s)
    end
  end

  test "login_code is written in the user's locale" do
    @user.update!(locale: "fr")

    assert_equal "123456 est votre code Dummy", login_code_mail.deliver_now.subject
  end

  test "login_code sends nothing for a decoy, a review account or a code that expired in the queue" do
    @challenge.update!(user: nil)
    assert_nil login_code_mail.deliver_now

    @challenge.update!(user: @user)
    Studio::Auth::ReviewAccounts.stubs(:include?).returns(true)
    assert_nil login_code_mail.deliver_now

    Studio::Auth::ReviewAccounts.unstub(:include?)
    assert_nil Mailer.with(challenge: @challenge, encrypted_code: "tampered").login_code.deliver_now
  end

  test "every locale has every key the English copy has" do
    english = keys(I18n.t("studio_auth", locale: :en))
    [:fr, :nl].each do |locale|
      assert_equal english, keys(I18n.t("studio_auth", locale: locale)), "#{locale} is missing keys"
    end
  end

  test "every email has a preview at /rails/mailers that renders" do
    preview = ActionMailer::Preview.find("studio/auth/mailer")
    users_before = User.count

    assert_equal ["locked", "login_code", "new_device", "reauthentication_code"], preview.emails.sort
    preview.emails.each do |email|
      mail = preview.call(email)
      assert_includes mail.subject, "Dummy", "#{email} preview did not render"
      assert_predicate mail.text_part.body.to_s, :present?
    end
    assert_equal users_before, User.count, "previews must not write to the database"
  end

  test "regional locales fill in even when the app does not list the base locale" do
    original = I18n.available_locales
    I18n.available_locales = [:en, :"fr-CA"]
    I18n.enforce_available_locales = true
    Studio::Auth::Locales.fill_regional

    assert_equal "Code incorrect. Vérifiez-le et réessayez.", I18n.t("studio_auth.flash.wrong_code", locale: :"fr-CA")
  ensure
    I18n.available_locales = original
  end

  private

  def login_code_mail
    Mailer.with(challenge: @challenge, encrypted_code: Studio::Auth::Secrets.encrypt("123456")).login_code
  end

  def keys(hash, prefix = nil)
    hash.flat_map { |key, value| value.is_a?(Hash) ? keys(value, [prefix, key].compact.join(".")) : [[prefix, key].compact.join(".")] }.sort
  end
end
