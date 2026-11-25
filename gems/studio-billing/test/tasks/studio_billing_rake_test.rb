require "test_helper"
require "rake"

class StudioBillingRakeTest < StudioBillingTestCase
  setup do
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load File.expand_path("../../lib/tasks/studio_billing.rake", __dir__)
  end

  test "studio_billing:check exits 1 on drift and applies nothing" do
    sync = stub(changes: [change(:create)], in_sync?: false)
    sync.expects(:apply!).never
    Studio::Billing::Sync.stubs(:new).returns(sync)

    error = assert_raises(SystemExit) { capture_io { Rake::Task["studio_billing:check"].invoke } }
    assert_equal 1, error.status
  end

  test "studio_billing:sync keeps a new webhook secret out of a non-interactive terminal" do
    result = Studio::Billing::Sync::Result.new(changes: [change(:create)], webhook_secret: "whsec_new_secret")
    Studio::Billing::Sync.stubs(:new).returns(stub(in_sync?: false, apply!: result))
    $stdout.stubs(:tty?).returns(false)

    output, = capture_io { Rake::Task["studio_billing:sync"].invoke }

    refute_includes output, "whsec_new_secret"
  end

  test "studio_billing:sync prints a new webhook secret to an interactive terminal" do
    result = Studio::Billing::Sync::Result.new(changes: [change(:create)], webhook_secret: "whsec_new_secret")
    Studio::Billing::Sync.stubs(:new).returns(stub(in_sync?: false, apply!: result))

    output, = capture_io do
      $stdout.stubs(:tty?).returns(true)
      Rake::Task["studio_billing:sync"].invoke
    end

    assert_includes output, "whsec_new_secret"
  end

  private

  def change(action)
    Studio::Billing::Sync::Change.new(action: action, subject: "webhook endpoint", detail: "new", perform: -> {})
  end
end
