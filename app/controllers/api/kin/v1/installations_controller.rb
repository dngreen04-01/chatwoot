# frozen_string_literal: true

# Layer 3 — Kin installations endpoint. Called by the Shopify app
# (personal-kin/kin) after provisioning a merchant to mirror the
# installation into Rails so Sidekiq jobs and Shopify webhooks can look
# up the row by `shopify_domain`.
#
# Auth: inherits `PlatformController` so the `api_access_token` header
# must match a `PlatformApp` access token (same as Chatwoot's platform
# endpoints). This is replaced by Shopify session-token middleware in 1.1.
module Api
  module Kin
    module V1
      class InstallationsController < PlatformController
        def create
          installation = ::Kin::ShopifyInstallation.find_or_initialize_by(
            shopify_domain: params[:shopify_domain]
          )

          installation.assign_attributes(
            account_id: params[:account_id],
            shopify_access_token: params[:shopify_access_token],
            shopify_store_name: params[:shopify_store_name],
            scopes: params[:scopes],
            installed_at: installation.installed_at || Time.current,
            uninstalled_at: nil
          )

          installation.save!

          render json: {
            id: installation.id,
            shopify_domain: installation.shopify_domain,
            account_id: installation.account_id,
            installed_at: installation.installed_at
          }, status: :created
        end
      end
    end
  end
end
