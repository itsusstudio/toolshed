require "test_helper"

class Studio::Monitoring::RequestSamplingTest < ActiveSupport::TestCase
  setup { Studio::Monitoring.config.stubs(:appsignal_ignored_paths).returns(["/admin"]) }

  test "#call keeps a request that falls inside the sample" do
    Appsignal.expects(:set_namespace).never

    call_middleware(path: "/recipes", roll: 0.1)
  end

  test "#call drops a request that falls outside the sample" do
    Appsignal.expects(:set_namespace).with("sampled_out")

    call_middleware(path: "/recipes", roll: 0.9)
  end

  test "#call keeps a slow request that falls outside the sample" do
    Appsignal.expects(:set_namespace).never

    call_middleware(path: "/recipes", roll: 0.9, duration: 0.6)
  end

  test "#call keeps a server error that falls outside the sample" do
    Appsignal.expects(:set_namespace).never

    call_middleware(path: "/recipes", roll: 0.9, status: 500)
  end

  test "#call keeps a request that reported a handled error and falls outside the sample" do
    Appsignal.expects(:set_namespace).never
    app = ->(_env) {
      Rails.error.report(RuntimeError.new("handled"), handled: true)
      [200, {}, []]
    }

    call_middleware(path: "/recipes", roll: 0.9, app: app)
  end

  test "#call drops the next request after one that reported a handled error" do
    reporting_app = ->(_env) {
      Rails.error.report(RuntimeError.new("handled"), handled: true)
      [200, {}, []]
    }
    Appsignal.stubs(:set_namespace)
    call_middleware(path: "/recipes", roll: 0.9, app: reporting_app)

    Appsignal.expects(:set_namespace).with("sampled_out")

    call_middleware(path: "/recipes", roll: 0.9)
  end

  test "#call drops a not found response that falls inside the sample" do
    Appsignal.expects(:set_namespace).with("sampled_out")

    call_middleware(path: "/missing", roll: 0.1, status: 404)
  end

  test "#call drops a slow request to an ignored path that falls inside the sample" do
    Appsignal.expects(:set_namespace).with("sampled_out")

    call_middleware(path: "/admin/users", roll: 0.1, duration: 0.6)
  end

  test "#call keeps a path that only starts with an ignored path" do
    Appsignal.expects(:set_namespace).never

    call_middleware(path: "/administrator", roll: 0.1)
  end

  test "#call returns the response when tagging the transaction fails" do
    Appsignal.stubs(:set_namespace).raises(RuntimeError, "agent gone")
    Rails.error.expects(:report)

    status, _headers, _body = call_middleware(path: "/recipes", roll: 0.9)

    assert_equal 200, status
  end

  test "the railtie inserts it inside DebugExceptions, before AppSignal inserts its instrumentation" do
    stack = DummyApp.middleware.map(&:klass)
    sampling = Studio::Monitoring::Railtie.initializers.find { it.name == "studio_monitoring.request_sampling" }

    assert_operator stack.index(Studio::Monitoring::RequestSampling), :>, stack.index(ActionDispatch::DebugExceptions)
    assert_includes Appsignal::Integrations::Railtie.initializers.map(&:name), sampling.before
  end

  private

  def call_middleware(path:, roll:, status: 200, duration: 0.01, app: ->(_env) { [status, {}, []] })
    Process.stubs(:clock_gettime).returns(0.0, duration)
    Random.stubs(:rand).returns(roll)

    Studio::Monitoring::RequestSampling.new(app).call(Rack::MockRequest.env_for(path))
  end
end
