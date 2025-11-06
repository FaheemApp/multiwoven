# frozen_string_literal: true

module Utils
  class HealthChecker
    def self.run
      health_check_port = ENV["MULTIWOVEN_WORKER_HEALTH_CHECK_PORT"] || 4567

      server = WEBrick::HTTPServer.new(Port: health_check_port)
      server.mount_proc "/health" do |_req, res|
        res.body = "Service is healthy"
      end

      trap "INT" do
        server.shutdown
      end

      Thread.new do
        # Ensure this thread doesn't hold onto a database connection
        # The health check doesn't need database access
        ActiveRecord::Base.connection_pool.release_connection if ActiveRecord::Base.connected?

        server.start
      rescue StandardError => e
        Rails.logger.error("Health check server error: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
      ensure
        # Clean up any connections if they were somehow established
        ActiveRecord::Base.connection_pool.release_connection if ActiveRecord::Base.connected?
      end
    end
  end
end
