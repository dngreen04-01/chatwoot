# Phase 1.0.e — prepare `kin_shopify_installations.shopify_access_token` for
# Rails 7 native `encrypts`. The Phase-0 migration named the column
# `shopify_access_token_ciphertext` to hint at encryption; Rails 7's
# `encrypts` macro doesn't require that suffix, so rename for a cleaner
# model accessor. Also add `scopes` (required by CLAUDE.md schema spec).
class PrepareKinShopifyInstallationsEncryption < ActiveRecord::Migration[7.1]
  def change
    rename_column :kin_shopify_installations, :shopify_access_token_ciphertext, :shopify_access_token
    add_column :kin_shopify_installations, :scopes, :string
  end
end
