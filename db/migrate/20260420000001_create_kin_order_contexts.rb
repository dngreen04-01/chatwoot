# Phase 1.4 — Cached Shopify order snapshot per conversation. Populated
# write-through by the Kin Shopify app when a conversation is opened:
# the loader queries Shopify GraphQL once, then PUTs the snapshot here
# so subsequent opens of the same conversation hit the cache in <500ms
# instead of the ~1s Shopify round-trip.
#
# Scoped by (account_id, conversation_id). One row per conversation
# max — hence the unique index.
class CreateKinOrderContexts < ActiveRecord::Migration[7.1]
  def change
    create_table :kin_order_contexts do |t|
      t.references :account, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.string :shopify_order_id
      t.string :shopify_order_number
      t.jsonb :order_data_json, null: false, default: {}
      t.datetime :last_synced_at, null: false
      t.text :last_sync_error

      t.timestamps
    end

    add_index :kin_order_contexts, [:account_id, :conversation_id], unique: true
  end
end
