# frozen_string_literal: true

# Layer 3 — Append-only audit row recording an agent's view of a
# contact or conversation (see Kin::ContactAccessLogDecorator).
#
# Writes go through .bulk_log so the decorator can fire from an
# around_action without paying a per-row validation pass on the hot
# request path.
#
# Schema: see db/migrate/20260423000001_create_kin_contact_access_logs.rb.
# == Schema Information
#
# Table name: kin_contact_access_logs
#
#  id              :bigint           not null, primary key
#  accessed_at     :datetime         not null
#  action          :string           not null
#  ip_address      :string
#  user_agent      :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  agent_id        :bigint           not null
#  contact_id      :bigint
#  conversation_id :bigint
#
# Indexes
#
#  index_kin_contact_access_logs_on_account_and_accessed  (account_id,accessed_at DESC)
#  index_kin_contact_access_logs_on_account_id            (account_id)
#  index_kin_contact_access_logs_on_agent_and_accessed    (agent_id,accessed_at DESC)
#  index_kin_contact_access_logs_on_agent_id              (agent_id)
#  index_kin_contact_access_logs_on_contact_id            (contact_id)
#  index_kin_contact_access_logs_on_conversation_id       (conversation_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (agent_id => users.id)
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => nullify
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => nullify
#
module Kin
  class ContactAccessLog < ApplicationRecord
    self.table_name = 'kin_contact_access_logs'

    ACTIONS = %w[show index].freeze

    belongs_to :account
    belongs_to :agent, class_name: 'User'
    belongs_to :contact, optional: true
    belongs_to :conversation, optional: true

    validates :action, presence: true, inclusion: { in: ACTIONS }
    validates :accessed_at, presence: true

    scope :recent, -> { order(accessed_at: :desc) }

    def self.bulk_log(rows)
      return if rows.blank?

      # rubocop:disable Rails/SkipsModelValidations
      insert_all(rows)
      # rubocop:enable Rails/SkipsModelValidations
    end
  end
end
