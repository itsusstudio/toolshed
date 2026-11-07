require "test_helper"

class Studio::Monitoring::JobSubscriberTest < ActiveSupport::TestCase
  test "#call logs a finished app job with its class as the source" do
    Studio::Monitoring::Logging.expects(:log_info).with(CleanupJob, "job_performed",
      properties: has_entries(queue: "default", success: true))

    Studio::Monitoring::JobSubscriber.new.call(event(CleanupJob.new))
  end

  test "#call logs a failed job at error level with the error class" do
    Studio::Monitoring::Logging.expects(:log_error).with(CleanupJob, "job_performed",
      properties: has_entries(success: false, message: "ArgumentError"))

    Studio::Monitoring::JobSubscriber.new.call(event(CleanupJob.new, error: ArgumentError.new))
  end

  test "#call skips framework jobs" do
    Studio::Monitoring::Logging.expects(:log_info).never

    Studio::Monitoring::JobSubscriber.new.call(event(FrameworkJob.new))
  end

  private

  def event(job, error: nil)
    ActiveSupport::Notifications::Event.new("perform.active_job", 0, 0.12, "id", {job: job, exception_object: error}.compact)
  end
end
