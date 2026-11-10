module Studio
  module Auth
    class MailDeliveryJob < ActionMailer::MailDeliveryJob
      RETRY_WAITS = [1.second, 3.seconds, 10.seconds, 30.seconds].freeze

      queue_as MAIL_QUEUE

      retry_on StandardError,
        attempts: RETRY_WAITS.size + 1,
        wait: ->(executions) { RETRY_WAITS.fetch(executions - 1, RETRY_WAITS.last) } do |job, error|
        Events.notify("mail_delivery_failed", mailer_action: job.arguments.second, error_class: error.class.name)
        ::Rails.error.report(error, handled: true, context: {mailer_action: job.arguments.second})
      end

      # A refused request fails the same way on every retry. A string, so
      # apps without Resend never load it.
      discard_on "Resend::Error::InvalidRequestError" do |job, _error|
        Events.notify("mail_rejected", mailer_action: job.arguments.second)
      end
    end
  end
end
