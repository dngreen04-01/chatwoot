# frozen_string_literal: true

# Layer 3 — Per-macro usage event (Phase 1.6). Written each time an agent
# sends a macro-backed reply; powers the 30-day bar chart and "uses"
# counter on the macro detail pane.
#
# Written transactionally with `kin_macros.usage_count` and `last_used_at`
# bumps in `Api::Kin::V1::MacroUsagesController#create`.
# == Schema Information
#
# Table name: kin_macro_usages
#
#  id              :bigint           not null, primary key
#  used_at         :datetime         not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  agent_id        :bigint           not null
#  conversation_id :bigint
#  macro_id        :bigint           not null
#
# Indexes
#
#  index_kin_macro_usages_on_account_and_used      (account_id,used_at DESC)
#  index_kin_macro_usages_on_account_id            (account_id)
#  index_kin_macro_usages_on_agent_id              (agent_id)
#  index_kin_macro_usages_on_conversation_id       (conversation_id)
#  index_kin_macro_usages_on_macro_id              (macro_id)
#  index_kin_macro_usages_on_macro_id_and_used_at  (macro_id,used_at DESC)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (agent_id => users.id)
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => nullify
#  fk_rails_...  (macro_id => kin_macros.id) ON DELETE => cascade
#
module Kin
  class MacroUsage < ApplicationRecord
    self.table_name = 'kin_macro_usages'

    belongs_to :macro, class_name: 'Kin::Macro', inverse_of: :usages
    belongs_to :account
    belongs_to :agent, class_name: 'User'
    belongs_to :conversation, optional: true

    validates :used_at, presence: true

    scope :trailing_30_days, -> { where('used_at >= ?', 30.days.ago) }
    scope :recent_first, -> { order(used_at: :desc) }
  end
end
