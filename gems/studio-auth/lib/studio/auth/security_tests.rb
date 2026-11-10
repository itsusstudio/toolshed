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

        test "studio-auth: an unknown address gets the same answer and no mail" do
          create_authentication_user("known@studio.com")

          perform_enqueued_jobs { post login_path, params: {email_address: "nobody@studio.com"} }
          unknown_location = response.location
          follow_redirect!
          unknown_page = comparable_page("nobody@studio.com")

          assert_empty ActionMailer::Base.deliveries
          reset!
          perform_enqueued_jobs { post login_path, params: {email_address: "known@studio.com"} }
          assert_equal unknown_location, response.location
          follow_redirect!
          assert_equal unknown_page, comparable_page("known@studio.com")
          assert_equal 1, ActionMailer::Base.deliveries.size
        end

        test "studio-auth: a code signs in once and resets the Rails session" do
          create_authentication_user("cook@studio.com")
          get login_path
          before = session.id

          code = request_authentication_code("cook@studio.com")
          post verify_path, params: {code: code}
          assert_redirected_to authentication_landing_path
          refute_equal before, session.id

          challenge = LoginChallenge.order(:created_at).last
          assert_equal :expired, Challenges.verify(id: challenge.id, code: code, purpose: "sign_in").status

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
          refute_includes LoginChallenge.pluck(:code_digest), code
        end

        test "studio-auth: five wrong codes end the challenge" do
          create_authentication_user("cook@studio.com")
          code = request_authentication_code("cook@studio.com")
          id = LoginChallenge.order(:created_at).last.id

          CODE_MAX_ATTEMPTS.times { post verify_path, params: {code: wrong_code(code)} }
          assert_response :redirect
          assert_equal :too_many_attempts, Challenges.verify(id: id, code: code, purpose: "sign_in").status
        end

        test "studio-auth: a second browser cannot reach the first browser's code" do
          create_authentication_user("cook@studio.com")
          code = request_authentication_code("cook@studio.com")

          attacker = open_session
          attacker.post login_path, params: {email_address: "cook@studio.com"}
          CODE_MAX_ATTEMPTS.times { attacker.post verify_path, params: {code: wrong_code(code)} }

          post verify_path, params: {code: code}
          assert_redirected_to authentication_landing_path
        end

        test "studio-auth: codes are filtered from logs" do
          filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
          assert_equal "[FILTERED]", filter.filter("code" => "123456")["code"]
        end

        test "studio-auth: wrong codes lock the account across challenges, but not for a known device" do
          create_authentication_user("cook@studio.com")
          owner_code = request_authentication_code("cook@studio.com")
          post verify_path, params: {code: owner_code}
          delete logout_path

          attacker = open_session
          (FAILURE_LIMIT / CODE_MAX_ATTEMPTS).times do
            attacker.post login_path, params: {email_address: "cook@studio.com"}
            travel CODE_RESEND_INTERVAL + 1.second
            CODE_MAX_ATTEMPTS.times { attacker.post verify_path, params: {code: "000000"} }
          end
          perform_enqueued_jobs
          assert(ActionMailer::Base.deliveries.any? { |mail| mail.subject == I18n.t("studio_auth.mailer.locked.subject", app_name: Auth.config.app_name) })

          ActionMailer::Base.deliveries.clear
          perform_enqueued_jobs { attacker.post login_path, params: {email_address: "cook@studio.com"} }
          assert_empty ActionMailer::Base.deliveries, "a locked account must not mail codes to an unknown device"

          code = request_authentication_code("cook@studio.com")
          post verify_path, params: {code: code}
          assert_redirected_to authentication_landing_path
        ensure
          travel_back
        end

        test "studio-auth: an expired or deleted session is signed out without errors" do
          create_authentication_user("cook@studio.com")
          post verify_path, params: {code: request_authentication_code("cook@studio.com")}

          travel SESSION_IDLE_TIMEOUT + 1.minute do
            get login_path
            assert_response :success
          end

          ::Session.delete_all
          get login_path
          assert_response :success
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

        # Where a fresh sign-in lands; override when the app sends people
        # somewhere other than root.
        def authentication_landing_path
          root_path
        end

        def comparable_page(email_address)
          response.body.gsub(email_address, "EMAIL").gsub(/name="authenticity_token" value="[^"]*"/, "")
        end

        def wrong_code(code)
          ((code.to_i + 1) % 1_000_000).to_s.rjust(6, "0")
        end
      end
    end
  end
end
