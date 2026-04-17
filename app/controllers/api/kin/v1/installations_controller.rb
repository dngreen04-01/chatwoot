# frozen_string_literal: true

# Layer 3 — Kin installations endpoint. Called by the Shopify app
# (personal-kin/kin) after provisioning a merchant to mirror the
# installation into Rails so Sidekiq jobs and Shopify webhooks can look
# up the row by `shopify_domain`.
#
# Auth: HMAC-SHA256 via `Api::Kin::BaseController` — see that file for
# the signing scheme and secret-handling rationale. The Shopify-app
# process does not hold any Chatwoot PlatformApp token.
module Api
  module Kin
    module V1
      class InstallationsController < BaseController
        def create
          account = Account.find_by(id: installation_params[:account_id])
          return render json: { error: 'account_not_found' }, status: :not_found if account.nil?

          installation = ::Kin::ShopifyInstallation.find_or_initialize_by(
            shopify_domain: installation_params[:shopify_domain]
          )

          installation.assign_attributes(
            account_id: account.id,
            shopify_access_token: installation_params[:shopify_access_token],
            shopify_store_name: installation_params[:shopify_store_name],
            scopes: installation_params[:scopes],
            installed_at: installation.installed_at || Time.current,
            uninstalled_at: nil
          )

          if installation.save
            render json: serialize(installation), status: :created
          else
            render json: { errors: installation.errors.full_messages }, status: :unprocessable_entity
          end
        end

        private

        def installation_params
          @installation_params ||= params.permit(
            :shopify_domain,
            :shopify_access_token,
            :shopify_store_name,
            :scopes,
            :account_id
          )
        end

        def serialize(installation)
          {
            id: installation.id,
            shopify_domain: installation.shopify_domain,
            account_id: installation.account_id,
            installed_at: installation.installed_at
          }
        end
      end
    end
  end
end
