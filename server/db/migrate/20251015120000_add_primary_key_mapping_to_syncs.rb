# frozen_string_literal: true

class AddPrimaryKeyMappingToSyncs < ActiveRecord::Migration[7.1]
  def change
    add_column :syncs, :primary_key_mapping, :jsonb, default: {}, null: false
  end
end
