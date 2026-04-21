# Phase 1.5 — Audit log for Shopify write-back actions (refund, cancel,
# edit shipping address, duplicate). One row per agent-initiated mutation.
# The Shopify app dispatches the GraphQL call directly against Shopify
# (Shape C: Remix owns Shopify, Rails is the book-of-record) and mirrors
# a row here — successful or not — for later audit, analytics, and
# support-on-support ("who refunded what, when?").
#
# Scoped by account for tenant isolation. Conversation link is optional
# because the audit surface is account-wide (Settings → Activity) even
# when the action was triggered from a conversation sidebar.
class CreateKinShopifyActions < ActiveRecord::Migration[7.1]
  def change
    create_table :kin_shopify_actions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :agent, null: false, foreign_key: { to_table: :users }
      t.references :conversation, null: true, foreign_key: { on_delete: :nullify }
      t.string :action_name, null: false
      t.string :shopify_order_id
      t.string :shopify_order_number
      t.jsonb :payload_json, null: false, default: {}
      t.jsonb :result_json, null: false, default: {}
      t.string :status, null: false
      t.text :error_message
      t.datetime :executed_at, null: false

      t.timestamps
    end

    add_index :kin_shopify_actions, [:account_id, :executed_at],
              order: { executed_at: :desc },
              name: 'index_kin_shopify_actions_on_account_and_executed'
    add_index :kin_shopify_actions, [:account_id, :conversation_id, :executed_at],
              order: { executed_at: :desc },
              name: 'index_kin_shopify_actions_on_conv_and_executed'
  end
end
