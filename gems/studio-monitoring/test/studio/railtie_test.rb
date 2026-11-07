require "test_helper"

class Studio::Monitoring::RailtieTest < ActionDispatch::IntegrationTest
  def app
    DummyApp
  end

  test "every request sets the request id" do
    get "/ping", headers: {"X-Request-Id" => "req-abc"}

    assert_equal "req-abc", response.parsed_body["request_id"]
  end

  test "the posthog-js session header sets the analytics session" do
    get "/ping", headers: {"X-POSTHOG-SESSION-ID" => "sess-header"}

    assert_equal "sess-header", response.parsed_body["session_id"]
  end

  test "page loads fall back to the session in the posthog-js cookie" do
    Studio::Monitoring.config.stubs(:posthog).returns(Studio::Monitoring::Configuration::PosthogProject.new(token: "phc_1", host: "h"))
    cookies["ph_phc_1_posthog"] = {"$sesid" => [1, "sess-cookie", 0]}.to_json

    get "/ping"

    assert_equal "sess-cookie", response.parsed_body["session_id"]
  end

  test "a malformed posthog-js cookie leaves the session empty" do
    Studio::Monitoring.config.stubs(:posthog).returns(Studio::Monitoring::Configuration::PosthogProject.new(token: "phc_1", host: "h"))
    cookies["ph_phc_1_posthog"] = "not json"

    get "/ping"

    assert_nil response.parsed_body["session_id"]
  end

  test "every job sets the job id" do
    job = JobIdRecordingJob.new
    job.perform_now

    assert_equal job.job_id, JobIdRecordingJob.seen_job_id
  end

  class JobIdRecordingJob < ApplicationJob
    cattr_accessor :seen_job_id

    def perform
      self.class.seen_job_id = Studio::Monitoring::Current.job_id
    end
  end

  test "the boot summary names the service, PostHog state and backends" do
    summary = Studio::Monitoring.summary

    assert_equal "dummy", summary[:service]
    assert_equal "off", summary[:posthog]
    assert_equal "rails,appsignal,posthog", summary[:log_backends]
    assert_equal "posthog", summary[:analytics_backends]
    assert_equal "off", summary[:otel]
  end

  test "lograge ignores the default actions and is off in local environments" do
    lograge = DummyApp.config.lograge

    assert_not lograge.enabled
    assert_includes lograge.ignore_actions, "Rails::HealthController#show"
  end
end
