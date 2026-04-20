# frozen_string_literal: true

# Layer 3 — Agent-authored note pinned to a contact. Distinct from
# Chatwoot's conversation-scoped internal notes (which live on the
# conversation thread); these persist across conversations and surface
# in the Notes tab of the Order Context sidebar.
#
# Schema: see db/migrate/20260420000002_create_kin_contact_notes.rb.
module Kin
  class ContactNote < ApplicationRecord
    self.table_name = 'kin_contact_notes'

    belongs_to :account
    belongs_to :contact
    belongs_to :author, class_name: 'User'

    validates :body, presence: true, length: { maximum: 10_000 }

    scope :ordered, -> { order(Arel.sql('pinned_at DESC NULLS LAST, created_at DESC')) }
  end
end
