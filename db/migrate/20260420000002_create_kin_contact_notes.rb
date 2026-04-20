# Phase 1.4 — Agent-authored notes pinned to a contact (distinct from
# Chatwoot conversation-scoped internal notes, which live in the
# conversation thread). Surfaced in the Notes tab of the Order Context
# sidebar and scoped per-account for tenant isolation.
#
# `pinned_at` nullable: NULL rows sort by `created_at DESC`; non-NULL
# sort ahead of NULL rows. The compound index supports that query.
class CreateKinContactNotes < ActiveRecord::Migration[7.1]
  def change
    create_table :kin_contact_notes do |t|
      t.references :account, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.datetime :pinned_at

      t.timestamps
    end

    add_index :kin_contact_notes, [:account_id, :contact_id, :pinned_at, :created_at],
              order: { pinned_at: 'DESC NULLS LAST', created_at: :desc },
              name: 'index_kin_contact_notes_on_scope_and_sort'
  end
end
