# Phase 1.6 — Reusable reply templates per account. Content supports
# `{{customer.*}} / {{order.*}} / {{shop.*}}` tokens resolved on the Remix
# side against the 1.4 order-context cache before insertion. `auto_apply_json`
# drives post-send side effects (tag + status change); `shortcut_key`
# enables `;wt`-style chord triggers in the composer.
#
# Account-scoped; follows the 1.4/1.5 Layer-3 conventions (see
# 20260421000001_create_kin_shopify_actions.rb).
class CreateKinMacros < ActiveRecord::Migration[7.1]
  def change
    create_table :kin_macros do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.text :content, null: false
      t.string :category, null: false, default: 'General'
      t.jsonb :channels_json, null: false, default: %w[email chat]
      t.references :created_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.integer :usage_count, null: false, default: 0
      t.datetime :last_used_at
      t.string :shortcut_key
      t.jsonb :auto_apply_json, null: false, default: {}

      t.timestamps
    end

    add_index :kin_macros, [:account_id, :category]
    add_index :kin_macros, [:account_id, :name], unique: true
    add_index :kin_macros, [:account_id, :shortcut_key],
              unique: true,
              where: 'shortcut_key IS NOT NULL',
              name: 'index_kin_macros_on_account_and_shortcut'
  end
end
