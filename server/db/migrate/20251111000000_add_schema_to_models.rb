# frozen_string_literal: true

class AddSchemaToModels < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_column :models, :schema, :jsonb, default: {}
    add_index :models, :schema, using: :gin, algorithm: :concurrently
  end
end
