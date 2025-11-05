# frozen_string_literal: true

module Middlewares
  class DatabaseMiddleware
    def call(_metadata)
      ActiveRecord::Base.connection_pool.with_connection do
        yield
      ensure
        # Clear active connections to release them back to the pool
        # The with_connection block already handles connection checkout/checkin
        ActiveRecord::Base.clear_active_connections!
      end
    end
  end
end
