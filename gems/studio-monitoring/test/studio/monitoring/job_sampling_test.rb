require "test_helper"

class Studio::Monitoring::JobSamplingTest < ActiveSupport::TestCase
  setup do
    transaction = stub(namespace: Appsignal::Transaction::BACKGROUND_JOB)
    Appsignal::Transaction.stubs(:current?).returns(true)
    Appsignal::Transaction.stubs(:current).returns(transaction)
  end

  test ".around keeps a job that falls inside the sample" do
    Appsignal.expects(:set_namespace).never

    run_job(roll: 0.1)
  end

  test ".around drops a job that falls outside the sample" do
    Appsignal.expects(:set_namespace).with("sampled_out")

    run_job(roll: 0.9)
  end

  test ".around keeps a slow job that falls outside the sample" do
    Appsignal.expects(:set_namespace).never

    run_job(roll: 0.9, duration: 2.0)
  end

  test ".around keeps a job that raises and falls outside the sample" do
    Appsignal.expects(:set_namespace).never

    assert_raises(RuntimeError) { run_job(roll: 0.9) { raise "boom" } }
  end

  test ".around keeps a job that reported a handled error and falls outside the sample" do
    Appsignal.expects(:set_namespace).never

    run_job(roll: 0.9) { Rails.error.report(RuntimeError.new("handled"), handled: true) }
  end

  test ".around leaves a job performed inside a request alone" do
    Appsignal::Transaction.stubs(:current).returns(stub(namespace: Appsignal::Transaction::HTTP_REQUEST))
    Appsignal.expects(:set_namespace).never

    run_job(roll: 0.9)
  end

  test ".around keeps a handled error the enclosing request already reported" do
    Appsignal::Transaction.stubs(:current).returns(stub(namespace: Appsignal::Transaction::HTTP_REQUEST))
    ActiveSupport::IsolatedExecutionState[Studio::Monitoring::RequestSampling::ERROR_REPORTED_KEY] = true

    run_job(roll: 0.9)

    assert ActiveSupport::IsolatedExecutionState[Studio::Monitoring::RequestSampling::ERROR_REPORTED_KEY],
      "expected the request's handled error flag to survive the job"
  ensure
    ActiveSupport::IsolatedExecutionState.delete(Studio::Monitoring::RequestSampling::ERROR_REPORTED_KEY)
  end

  test ".around finishes the job when tagging the transaction fails" do
    Appsignal.stubs(:set_namespace).raises(RuntimeError, "agent gone")
    Rails.error.expects(:report)

    assert_equal :done, run_job(roll: 0.9) { :done }
  end

  test ".around leaves a job performed inside another job to the outer job" do
    Process.stubs(:clock_gettime).returns(0.0, 0.0, 0.01, 0.01)
    Random.stubs(:rand).returns(0.9)
    Appsignal.expects(:set_namespace).never

    assert_raises(RuntimeError) do
      Studio::Monitoring::JobSampling.around(nil) do
        Studio::Monitoring::JobSampling.around(nil) {}
        raise "boom"
      end
    end
  end

  test "the railtie samples framework jobs too" do
    Random.stubs(:rand).returns(0.9)
    Appsignal.expects(:set_namespace).with("sampled_out")

    FrameworkJob.perform_now
  end

  private

  def run_job(roll:, duration: 0.01, &work)
    Process.stubs(:clock_gettime).returns(0.0, duration)
    Random.stubs(:rand).returns(roll)
    result = nil

    Studio::Monitoring::JobSampling.around(nil) { result = work&.call }
    result
  end
end
