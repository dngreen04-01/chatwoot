# frozen_string_literal: true

# Layer 3 — Audit trail for PII access. One row per agent `show` or
# `index` against Api::V1::Accounts::ContactsController or
# Api::V1::Accounts::ConversationsController (see
# app/decorators/kin/contact_access_log_decorator.rb).
#
# Backs the 1.0.i Protected Customer Data matrix row "Access → Log
# access to PII" (Docs/PHASE-1-PLAN.md §1.0.i).
#
# contact_id / conversation_id are nullable + on_delete: :nullify so
# the audit row survives a downstream delete of the accessed record
# (which is the point of an audit log).
class CreateKinContactAccessLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :kin_contact_access_logs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :agent, null: false, foreign_key: { to_table: :users }
      t.references :contact, null: true, foreign_key: { on_delete: :nullify }
      t.references :conversation, null: true, foreign_key: { on_delete: :nullify }
      t.string :action, null: false
      t.datetime :accessed_at, null: false
      t.string :ip_address
      t.string :user_agent

      t.timestamps
    end

    add_index :kin_contact_access_logs, [:account_id, :accessed_at],
              order: { accessed_at: :desc },
              name: 'index_kin_contact_access_logs_on_account_and_accessed'
    add_index :kin_contact_access_logs, [:agent_id, :accessed_at],
              order: { accessed_at: :desc },
              name: 'index_kin_contact_access_logs_on_agent_and_accessed'
  end
end
