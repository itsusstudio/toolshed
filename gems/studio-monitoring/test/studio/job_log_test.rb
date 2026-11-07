require "test_helper"

class Studio::Monitoring::JobLogTest < ActiveSupport::TestCase
  test "#call logs a finished app job with its class as the source" do
    Studio::Monitoring::Events.expects(:info).with("job_performed", has_entries(source: "CleanupJob", queue: "default", success: true))

    Studio::Monitoring::JobLog.call(event(CleanupJob.new))
  end

  test "#call logs a failed job at error level with the error class" do
    Studio::Monitoring::Events.expects(:error).with("job_performed", has_entries(success: false, message: "ArgumentError"))

    Studio::Monitoring::JobLog.call(event(CleanupJob.new, error: ArgumentError.new))
  end

  test "#call skips framework jobs" do
    Studio::Monitoring::Events.expects(:info).never

    Studio::Monitoring::JobLog.call(event(FrameworkJob.new))
  end

  private

  def event(job, error: nil)
    ActiveSupport::Notifications::Event.new("perform.active_job", 0, 0.12, "id", {job: job, exception_object: error}.compact)
  end
end
