require "test_helper"

class Studio::Monitoring::LoggingTest < ActiveSupport::TestCase
  test ".log_info includes the caller class, actor, tenant and app properties" do
    TestContext.user_id = 42
    TestContext.shop_id = 7
    TestContext.platform = "ios"

    Rails.logger.expects(:info).with { |line|
      line.include?("source=Studio::Monitoring::LoggingTest") && line.include?("actor_id=42") &&
        line.include?("tenant_id=7") && line.include?("platform=ios")
    }

    Studio::Monitoring::Logging.log_info(self, "recipe_url_import")
  end

  test ".log_info includes the request and job ids so lines join their request or job line" do
    Studio::Monitoring::Current.request_id = "req-1"
    Studio::Monitoring::Current.job_id = "job-1"

    Rails.logger.expects(:info).with { |line| line.include?("request_id=req-1") && line.include?("job_id=job-1") }

    Studio::Monitoring::Logging.log_info(self, "bulk_import")
  end

  test ".log_info names the class when called from a class method" do
    Rails.logger.expects(:info).with { |line| line.include?("source=CleanupJob") }

    Studio::Monitoring::Logging.log_info(CleanupJob, "cleanup")
  end

  test ".log_info omits keys that are nil" do
    Rails.logger.expects(:info).with { |line| !line.include?("actor_id") && !line.include?("tenant_id") && !line.include?("platform") }

    Studio::Monitoring::Logging.log_info(self, "recipe_url_import")
  end

  test ".log_info quotes values containing spaces so logfmt parses them as one attribute" do
    Rails.logger.expects(:info).with { |line| line.include?('reason="page has too little content"') }

    Studio::Monitoring::Logging.log_info(self, "recipe_import", properties: {reason: "page has too little content"})
  end

  test ".log_info lets explicit properties override defaults" do
    Rails.logger.expects(:info).with { |line| line.include?("locale=fr") }

    Studio::Monitoring::Logging.log_info(self, "recipe_import", properties: {locale: "fr"})
  end

  test ".log_warn logs at warn level with the event name first" do
    Rails.logger.expects(:warn).with { |line| line.start_with?("recipe_import ") }

    Studio::Monitoring::Logging.log_warn(self, "recipe_import")
  end

  test "every backend gets the level, line, event name and payload" do
    backend = mock("backend")
    backend.expects(:log).with { |level, line, message:, payload:|
      level == :info && line.start_with?("recipe_import") && message == "recipe_import" && payload[:recipe_id] == 7
    }
    Studio::Monitoring::Logging.stubs(:backends).returns([backend])

    Studio::Monitoring::Logging.log_info(self, "recipe_import", properties: {recipe_id: 7})
  end
end
