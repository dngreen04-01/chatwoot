# Phase 1.6 — Per-macro usage log. Feeds the 30-day bar chart and "uses"
# count on the detail pane; written transactionally alongside
# `kin_macros.usage_count` and `last_used_at` bumps whenever an agent sends
# a macro-backed reply.
#
# Cascade-delete: if the parent macro is removed, its usage history goes
# with it. Conversation link is nullified (not cascaded) so usage rows
# survive conversation deletion.
class CreateKinMacroUsages < ActiveRecord::Migration[7.1]
  def change
    create_table :kin_macro_usages do |t|
      t.references :macro,
                   null: false,
                   foreign_key: { to_table: :kin_macros, on_delete: :cascade }
      t.references :account, null: false, foreign_key: true
      t.references :agent, null: false, foreign_key: { to_table: :users }
      t.references :conversation, null: true, foreign_key: { on_delete: :nullify }
      t.datetime :used_at, null: false

      t.timestamps
    end

    add_index :kin_macro_usages, [:account_id, :used_at],
              order: { used_at: :desc },
              name: 'index_kin_macro_usages_on_account_and_used'
    add_index :kin_macro_usages, [:macro_id, :used_at], order: { used_at: :desc }
  end
end
