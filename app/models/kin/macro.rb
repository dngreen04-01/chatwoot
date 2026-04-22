# frozen_string_literal: true

# Layer 3 — Kin macro (Phase 1.6). Reusable reply template per account
# with `{{customer.*}} / {{order.*}} / {{shop.*}}` token support, optional
# keyboard chord (`shortcut_key`), and optional `auto_apply_json`
# post-send side effects (tag + status change).
#
# Distinct from Chatwoot's core `Macro` model (which drives automation
# rules). Namespaced under `Kin::`; the table name is pinned explicitly
# so the Rails autoloader never crosses it with `macros`.
#
# Schema: see db/migrate/20260422000001_create_kin_macros.rb.
# == Schema Information
#
# Table name: kin_macros
#
#  id              :bigint           not null, primary key
#  auto_apply_json :jsonb            not null
#  category        :string           default("General"), not null
#  channels_json   :jsonb            not null
#  content         :text             not null
#  last_used_at    :datetime
#  name            :string           not null
#  shortcut_key    :string
#  usage_count     :integer          default(0), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  created_by_id   :bigint
#
# Indexes
#
#  index_kin_macros_on_account_and_shortcut     (account_id,shortcut_key) UNIQUE WHERE (shortcut_key IS NOT NULL)
#  index_kin_macros_on_account_id               (account_id)
#  index_kin_macros_on_account_id_and_category  (account_id,category)
#  index_kin_macros_on_account_id_and_name      (account_id,name) UNIQUE
#  index_kin_macros_on_created_by_id            (created_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#
module Kin
  class Macro < ApplicationRecord
    self.table_name = 'kin_macros'

    CHANNELS = %w[email chat].freeze

    belongs_to :account
    belongs_to :created_by, class_name: 'User', optional: true
    has_many :usages, class_name: 'Kin::MacroUsage', dependent: :destroy, inverse_of: :macro

    validates :name, presence: true, uniqueness: { scope: :account_id, case_sensitive: false }
    validates :content, presence: true
    validates :category, presence: true

    scope :recent_first, -> { order(updated_at: :desc) }
    scope :for_category, ->(category) { where(category: category) }
  end
end
