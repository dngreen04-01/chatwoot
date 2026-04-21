# frozen_string_literal: true

# Layer 3 — Audit record for a Shopify write-back action (Phase 1.5).
# Written once per agent-initiated mutation, regardless of outcome. The
# Shopify app is the caller; this model is the append-only log it writes
# to via `POST /api/kin/v1/shopify_actions`.
#
# Schema: see db/migrate/20260421000001_create_kin_shopify_actions.rb.
# `action_name` (not `action`) because `action` collides with Rails'
# routing vocabulary; we translate to/from `action` at the wire layer.
module Kin
  class ShopifyAction < ApplicationRecord
    self.table_name = 'kin_shopify_actions'

    ACTIONS = %w[refund cancel edit_shipping_address duplicate].freeze
    STATUSES = %w[succeeded failed].freeze

    belongs_to :account
    belongs_to :agent, class_name: 'User'
    belongs_to :conversation, optional: true

    validates :action_name, inclusion: { in: ACTIONS }
    validates :status, inclusion: { in: STATUSES }
    validates :executed_at, presence: true

    scope :recent, -> { order(executed_at: :desc) }
    scope :for_conversation, ->(id) { where(conversation_id: id) }
  end
end
