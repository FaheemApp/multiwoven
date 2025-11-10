# frozen_string_literal: true

require "set"
module ReverseEtl
  module Extractors
    class IncrementalDelta < Base
      # TODO: Make it as class method
      def read(sync_run_id, activity)
        total_query_rows = 0
        skipped_rows = 0

        sync_run = SyncRun.find(sync_run_id)

        return log_sync_run_error(sync_run) unless sync_run.may_query?

        sync_run.query!

        source_client = setup_source_client(sync_run.sync)

        batch_query_params = batch_params(source_client, sync_run)
        model = sync_run.sync.model
        initial_cursor_field_value = sync_run.sync.current_cursor_field

        seen_primary_keys = Set.new

        ReverseEtl::Utils::BatchQuery.execute_in_batches(batch_query_params) do |records,
          current_offset, last_cursor_field_value|

          total_query_rows += records.count
          skipped_rows += process_records(records, sync_run, model, seen_primary_keys)
          sync_run.update(current_offset:, total_query_rows:, skipped_rows:)
          sync_run.sync.update(current_cursor_field: last_cursor_field_value)
          heartbeat(activity, sync_run, initial_cursor_field_value)
        end
        enqueue_deleted_records(sync_run, seen_primary_keys)
        # change state querying to queued
        sync_run.queue!
      ensure
        # Source client connections are closed in each read() call's ensure block
        # This is a safety net to log completion
        Rails.logger.debug({
          message: "[MYSQL] Extractor activity completed - source connections cleaned up via ensure blocks",
          sync_run_id:,
          total_query_rows:,
          skipped_rows:
        }.to_s) if sync_run
      end

      private

      # TODO: refactor this method
      def process_records(records, sync_run, model, seen_primary_keys)
        Parallel.map(records, in_threads: THREAD_COUNT) do |message|
          record = message.record
          fingerprint = generate_fingerprint(record.data)
          sync_record = process_record(record, sync_run, model)
          seen_primary_keys << sync_record.primary_key if sync_record&.primary_key
          update_or_create_sync_record(sync_record, record, sync_run, fingerprint) ? 0 : 1
        end.sum
      end
    end
  end
end
