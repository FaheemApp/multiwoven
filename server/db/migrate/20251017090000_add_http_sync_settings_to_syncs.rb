# frozen_string_literal: true

class AddHttpSyncSettingsToSyncs < ActiveRecord::Migration[7.1]
  class MigrationConnector < ApplicationRecord
    self.table_name = "connectors"
  end

  class MigrationSync < ApplicationRecord
    self.table_name = "syncs"
    belongs_to :destination, class_name: "AddHttpSyncSettingsToSyncs::MigrationConnector", optional: true
  end

  def up
    add_column :syncs, :http_sync_settings, :jsonb, default: {}, null: false
    backfill_http_sync_settings
  end

  def down
    remove_column :syncs, :http_sync_settings
  end

  private

  def backfill_http_sync_settings
    say_with_time "Backfilling HTTP sync settings for existing HTTP destinations" do
      MigrationSync.reset_column_information
      MigrationSync.joins(:destination)
                   .where("LOWER(connectors.connector_name) = ?", "http")
                   .find_each do |sync|
        destination_config = (sync.destination&.configuration || {}).with_indifferent_access
        settings = {}

        events = Array(destination_config[:events]).map(&:to_s).presence
        settings[:events] = events if events.present?

        batch_size = destination_config[:batch_size].to_i
        settings[:batch_size] = batch_size if batch_size.positive?

        next if settings.blank?

        sync.update_columns(http_sync_settings: settings)
      end
    end
  end
end
