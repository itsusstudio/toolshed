require "test_helper"

class Studio::Monitoring::JobLogTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

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

  test "#call records job.duration for app and framework jobs" do
    Studio::Monitoring::Metrics.expects(:record_duration).with("job.duration", 120.0, tags: {job: "CleanupJob", queue: "default", ok: false})
    Studio::Monitoring::Metrics.expects(:record_duration).with("job.duration", 120.0, tags: {job: "FrameworkJob", queue: "default", ok: true})

    Studio::Monitoring::JobLog.call(event(CleanupJob.new, error: ArgumentError.new))
    Studio::Monitoring::JobLog.call(event(FrameworkJob.new))
  end

  test ".record_queue_wait measures from enqueue" do
    freeze_time
    job = CleanupJob.new
    job.enqueued_at = 3.seconds.ago

    Studio::Monitoring::Metrics.expects(:record_duration).with("job.queue_wait", 3_000.0, tags: {queue: "default"})

    Studio::Monitoring::JobLog.record_queue_wait(job)
  end

  test ".record_queue_wait measures from the scheduled time, not the enqueue" do
    freeze_time
    job = CleanupJob.new
    job.enqueued_at = 1.hour.ago
    job.scheduled_at = 2.seconds.ago

    Studio::Monitoring::Metrics.expects(:record_duration).with("job.queue_wait", 2_000.0, tags: {queue: "default"})

    Studio::Monitoring::JobLog.record_queue_wait(job)
  end

  test ".record_queue_wait skips a job run without enqueueing" do
    Studio::Monitoring::Metrics.expects(:record_duration).never

    Studio::Monitoring::JobLog.record_queue_wait(CleanupJob.new)
  end

  private

  def event(job, error: nil)
    ActiveSupport::Notifications::Event.new("perform.active_job", 0, 0.12, "id", {job: job, exception_object: error}.compact)
  end
end
