require "logger"

module Studio
  module Monitoring
    class LogrageLogger < ::Logger
      def initialize
        super(nil)
      end

      # Logger#info(hash) arrives here as add(INFO, nil, hash).
      def add(severity, message = nil, progname = nil)
        request = message || progname || (yield if block_given?)
        level = (request[:status].to_i >= 500) ? :log_error : :log_info
        properties = request.merge(source: "#{request[:controller]}##{request[:action]}")
        Logging.public_send(level, self.class, "http_request", properties: properties)
        true
      end
    end
  end
end
