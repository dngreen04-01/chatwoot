# frozen_string_literal: true

# Layer 3 — Kin-specific model. Cached Shopify order snapshot per
# conversation. See db/migrate/20260420000001_create_kin_order_contexts.rb.
#
# Written write-through by the Shopify app via PUT
# /api/kin/v1/order_contexts/:conversation_id. Read back by the same app
# on conversation open to serve a <500ms cached render. Column-level
# encryption is not applied: `order_data_json` is protected by Cloud SQL
# CMEK at rest + HTTPS in transit per the 1.0.i matrix.
module Kin
  class OrderContext < ApplicationRecord
    self.table_name = 'kin_order_contexts'

    belongs_to :account
    belongs_to :conversation

    validates :last_synced_at, presence: true
    validates :account_id, uniqueness: { scope: :conversation_id }

    scope :stale, ->(ttl) { where(last_synced_at: ...ttl.ago) }
  end
end
