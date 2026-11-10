require "test_helper"

class Studio::Auth::SignInMailerTest < ActionMailer::TestCase
  setup do
    @user = User.create!(email_address: "cook@studio.com")
    @login_code = Studio::Auth::LoginCode.create!(
      user: @user, code_digest: "digest", expires_at: 10.minutes.from_now,
      ip_address: "1.2.3.4", user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15"
    )
  end

  test "login_code has text and HTML parts, the code in the subject, and only the support and legal links" do
    mail = login_code_mail.deliver_now

    assert_equal "123456 is your Dummy code", mail.subject
    assert_equal ["hello@dummy.app"], mail.from
    assert_equal "multipart/alternative", mail.mime_type
    assert_equal "auto-generated", mail["Auto-Submitted"].value
    assert_includes mail.text_part.body.to_s, "This code expires in 10 minutes."
    [mail.text_part, mail.html_part].each do |part|
      assert_includes part.body.to_s, "123456"
      assert_includes part.body.to_s, "safely ignore it"
      assert_no_match(%r{https?://(?!dummy\.app/(mail/logo\.png|terms|privacy)")}, part.body.to_s)
      assert_equal ["mailto:support@dummy.app", "https://dummy.app/terms", "https://dummy.app/privacy"], part.body.to_s.scan(/href="([^"]+)"/).flatten.uniq if part == mail.html_part
    end
  end

  test "the footer links the app's legal pages" do
    body = login_code_mail.deliver_now.html_part.body.to_s

    assert_includes body, %(href="https://dummy.app/terms")
    assert_includes body, %(href="https://dummy.app/privacy")
  end

  test "the app's logo heads the mail, with nothing attached" do
    mail = login_code_mail.deliver_now

    assert_includes mail.html_part.body.to_s, %(src="https://dummy.app/mail/logo.png" alt="Dummy")
    assert_empty mail.attachments
  end

  test "login_code is written in the user's locale" do
    @user.update!(locale: "fr")

    assert_equal "123456 est votre code Dummy", login_code_mail.deliver_now.subject
  end

  test "login_code sends nothing for a decoy, an app review account or a code that expired in the queue" do
    @login_code.update!(user: nil)
    assert_nil login_code_mail.deliver_now

    @login_code.update!(user: @user)
    Studio::Auth::AppReviewAccounts.stubs(:include?).returns(true)
    assert_nil login_code_mail.deliver_now

    Studio::Auth::AppReviewAccounts.unstub(:include?)
    assert_nil Studio::Auth::SignInMailer.with(login_code: @login_code, encrypted_code: "tampered").login_code.deliver_now
  end

  test "every locale has every key the English copy has" do
    english = keys(I18n.t("studio_auth", locale: :en))
    [:fr, :nl].each do |locale|
      assert_equal english, keys(I18n.t("studio_auth", locale: locale)), "#{locale} is missing keys"
    end
  end

  test "every email has a preview at /rails/mailers that renders" do
    preview = ActionMailer::Preview.find("studio/auth/sign_in_mailer")
    users_before = User.count

    assert_equal ["locked", "login_code"], preview.emails.sort
    preview.emails.each do |email|
      mail = preview.call(email)
      assert_includes mail.subject, "Dummy", "#{email} preview did not render"
      assert_predicate mail.text_part.body.to_s, :present?
    end
    assert_equal users_before, User.count, "previews must not write to the database"
  end

  test "a regional locale gets the gem's strings even when the app doesn't offer the bare language" do
    with_locales([:en, :"fr-CA"]) do
      assert_equal "Code incorrect. Vérifiez-le et réessayez.", I18n.t("studio_auth.flash.wrong_code", locale: :"fr-CA")
    end
  end

  test "the app's own strings win over the gem's" do
    override = File.join(DUMMY_ROOT, "tmp/override.fr-CA.yml")
    File.write(override, {"fr-CA" => {"studio_auth" => {"flash" => {"wrong_code" => "Mauvais code."}}}}.to_yaml)
    I18n.load_path << override

    with_locales([:en, :"fr-CA"]) do
      assert_equal "Mauvais code.", I18n.t("studio_auth.flash.wrong_code", locale: :"fr-CA")
    end
  ensure
    I18n.load_path.delete(override)
    I18n.reload!
  end

  private

  def with_locales(locales)
    original = I18n.available_locales
    I18n.available_locales = locales
    I18n.enforce_available_locales = true
    I18n.reload!
    yield
  ensure
    I18n.available_locales = original
    I18n.reload!
  end

  def login_code_mail
    Studio::Auth::SignInMailer.with(login_code: @login_code, encrypted_code: Studio::Auth::Secrets.encrypt("123456")).login_code
  end

  def keys(hash, prefix = nil)
    hash.flat_map { |key, value| value.is_a?(Hash) ? keys(value, [prefix, key].compact.join(".")) : [[prefix, key].compact.join(".")] }.sort
  end
end
