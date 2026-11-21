module Studio
  module Auth
    module SecurityTests
      extend ActiveSupport::Concern

      included do
        include ActiveJob::TestHelper
        include ActiveSupport::Testing::TimeHelpers

        setup do
          ActionMailer::Base.deliveries.clear
          Rails.cache.clear
        end

        test "studio-auth: the sign-in page posts an email address to login" do
          get login_path

          assert_response :success
          assert_select "form[action=?] input[name=email_address]", login_path
        end

        test "studio-auth: an address with no account is told so and gets no mail" do
          assert_no_difference -> { LoginCode.count } do
            perform_enqueued_jobs { post login_path, params: {email_address: "nobody@studio.com"} }
          end

          assert_redirected_to signup_path
          follow_redirect!
          assert_select "#studio-auth-sign-up-no-account"
          assert_empty ActionMailer::Base.deliveries
        end

        test "studio-auth: signing up writes no user before its code checks out" do
          assert_no_difference -> { ::User.count } do
            params = {full_name: "New Person", email_address: "new@studio.com"}
            perform_enqueued_jobs { post signup_path, params: params }
          end
          assert_redirected_to verify_path
        end

        test "studio-auth: a code signs in once and resets the Rails session" do
          create_authentication_user("cook@studio.com")
          get login_path
          before = session.id

          code = request_authentication_code("cook@studio.com")
          post verify_path, params: {code: code}
          assert_signed_in
          refute_equal before, session.id

          login_code = LoginCode.order(:created_at).last
          assert_equal :expired, VerifyCode.call(id: login_code.id, code: code).status

          delete logout_path
          assert_nil ::Session.find_by(user: ::User.find_by(email_address: "cook@studio.com"))
        end

        test "studio-auth: the code is never stored or enqueued in plain text" do
          create_authentication_user("cook@studio.com")
          post login_path, params: {email_address: "cook@studio.com"}
          job_arguments = enqueued_jobs.join
          perform_enqueued_jobs
          code = authentication_code_from_mail

          assert_match(/\A\d{6}\z/, code)
          refute_includes job_arguments, code
          refute_includes LoginCode.pluck(:code_digest), code
        end

        test "studio-auth: five wrong guesses end a code" do
          create_authentication_user("cook@studio.com")
          code = request_authentication_code("cook@studio.com")
          id = LoginCode.order(:created_at).last.id

          LoginCode::MAX_ATTEMPTS.times { post verify_path, params: {code: wrong_code(code)} }
          assert_response :redirect
          assert_equal :too_many_attempts, VerifyCode.call(id: id, code: code).status
        end

        test "studio-auth: a second browser cannot reach the first browser's code" do
          create_authentication_user("cook@studio.com")
          code = request_authentication_code("cook@studio.com")

          attacker = open_session
          attacker.post login_path, params: {email_address: "cook@studio.com"}
          LoginCode::MAX_ATTEMPTS.times { attacker.post verify_path, params: {code: wrong_code(code)} }

          post verify_path, params: {code: code}
          assert_signed_in
        end

        test "studio-auth: codes are filtered from logs" do
          filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
          assert_equal "[FILTERED]", filter.filter("code" => "123456")["code"]
        end

        test "studio-auth: wrong codes lock the account across codes, but not for a known device" do
          create_authentication_user("cook@studio.com")
          owner_code = request_authentication_code("cook@studio.com")
          post verify_path, params: {code: owner_code}
          delete logout_path

          attacker = open_session
          (SignInLimits::LOCKOUT_WRONG_CODES / LoginCode::MAX_ATTEMPTS).times do
            attacker.post login_path, params: {email_address: "cook@studio.com"}
            travel SignInLimits::RESEND_INTERVAL + 1.second
            LoginCode::MAX_ATTEMPTS.times { attacker.post verify_path, params: {code: "000000"} }
          end
          perform_enqueued_jobs
          locked_subject = I18n.t("studio_auth.sign_in_mailer.locked.subject", app_name: Auth.config.app_name)
          assert(ActionMailer::Base.deliveries.any? { |mail| mail.subject == locked_subject })

          ActionMailer::Base.deliveries.clear
          perform_enqueued_jobs { attacker.post login_path, params: {email_address: "cook@studio.com"} }
          assert_empty ActionMailer::Base.deliveries, "a locked account must not mail codes to an unknown device"

          code = request_authentication_code("cook@studio.com")
          post verify_path, params: {code: code}
          assert_signed_in
        ensure
          travel_back
        end

        test "studio-auth: signing out a device only reaches the signed-in user's own sessions" do
          victim_session = create_authentication_user("victim@studio.com").sessions.create!
          create_authentication_user("cook@studio.com")
          post verify_path, params: {code: request_authentication_code("cook@studio.com")}

          delete logout_session_path(victim_session)

          assert ::Session.exists?(victim_session.id)
          assert_signed_in
        end

        test "studio-auth: an expired or deleted session is signed out without errors" do
          create_authentication_user("cook@studio.com")
          post verify_path, params: {code: request_authentication_code("cook@studio.com")}

          travel Auth.config.session_idle_timeout + 1.minute do
            get login_path
            assert_response :success
          end

          ::Session.delete_all
          get login_path
          assert_response :success
        end

        test "studio-auth: every cable channel says who may subscribe" do
          ::Rails.application.eager_load!
          assert_empty Cable.unchecked_channels(::Rails.root.join("app")),
            "include Studio::Auth::ForCableChannel and define authorized? in each of these channels"
        end

        test "studio-auth: Turbo streams go through the app's StreamsChannel" do
          views = ::Rails.root.glob("app/views/**/*.erb")
          return pass if views.none? { File.read(it).include?("turbo_stream_from") }

          ::Rails.application.eager_load!
          assert defined?(::StreamsChannel) && ::StreamsChannel < ::Turbo::StreamsChannel,
            "define StreamsChannel < Turbo::StreamsChannel, including Studio::Auth::ForCableChannel"
        end

        private

        def request_authentication_code(email_address)
          ActionMailer::Base.deliveries.clear
          perform_enqueued_jobs { post login_path, params: {email_address: email_address} }
          authentication_code_from_mail
        end

        def authentication_code_from_mail
          ActionMailer::Base.deliveries.last&.text_part&.body.to_s[/\b\d{6}\b/]
        end

        def assert_signed_in
          assert_response :see_other
          refute_includes [login_url, verify_url], response.location
        end

        def wrong_code(code)
          ((code.to_i + 1) % 1_000_000).to_s.rjust(6, "0")
        end
      end
    end
  end
end
