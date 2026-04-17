# frozen_string_literal: true

# Layer 3 — Kin-specific model. Represents a single Shopify store's
# installation of the Kin app. Paired with the Prisma `Session` row on the
# TypeScript side (see personal-kin/kin/app/lib/installations.server.ts);
# this row is written via POST /api/kin/v1/installations on install.
#
# Schema: see db/migrate/20260417000001_create_kin_shopify_installations.rb
# + 20260417020001_prepare_kin_shopify_installations_encryption.rb
module Kin
  class ShopifyInstallation < ApplicationRecord
    self.table_name = 'kin_shopify_installations'

    belongs_to :account

    encrypts :shopify_access_token if Chatwoot.encryption_configured?

    validates :shopify_domain, presence: true, uniqueness: true
    validates :shopify_access_token, presence: true
  end
end
