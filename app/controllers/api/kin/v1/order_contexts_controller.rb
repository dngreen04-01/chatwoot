# frozen_string_literal: true

# Layer 3 — Kin order-context cache endpoint. Called by the Shopify app's
# conversation-detail loader. All calls are HMAC-authenticated via
# `Api::Kin::BaseController`.
#
# Flow:
#   1. Shopify app opens conversation → POST .../lookup with
#      {account_id, conversation_id}. Returns cached snapshot or
#      {status: "miss"}.
#   2. On miss (or explicit re-sync), Shopify app fetches from Shopify
#      GraphQL then POSTs .../upsert to write-through the cache.
#   3. Retention sweep or uninstall triggers .../destroy.
#
# Shape chosen to keep everything under HMAC body signing — GETs with
# scoping query params would bypass body-HMAC replay protection.
module Api
  module Kin
    module V1
      class OrderContextsController < BaseController
        def lookup
          cache = ::Kin::OrderContext.find_by(
            account_id: scope_params[:account_id],
            conversation_id: scope_params[:conversation_id]
          )

          return render(json: { status: 'miss' }) if cache.nil?

          render json: serialize(cache)
        end

        def upsert
          return render(json: { error: 'account_not_found' }, status: :not_found) if account.nil?
          return render(json: { error: 'conversation_not_found' }, status: :not_found) if conversation.nil?

          context = ::Kin::OrderContext.find_or_initialize_by(
            account_id: account.id,
            conversation_id: conversation.id
          )
          context.assign_attributes(
            shopify_order_id: upsert_params[:shopify_order_id],
            shopify_order_number: upsert_params[:shopify_order_number],
            order_data_json: upsert_params[:order_data_json] || {},
            last_synced_at: Time.current,
            last_sync_error: upsert_params[:last_sync_error]
          )

          if context.save
            render json: serialize(context)
          else
            render json: { errors: context.errors.full_messages }, status: :unprocessable_entity
          end
        end

        def destroy
          cache = ::Kin::OrderContext.find_by(
            account_id: scope_params[:account_id],
            conversation_id: scope_params[:conversation_id]
          )
          cache&.destroy
          head :no_content
        end

        private

        def scope_params
          @scope_params ||= params.permit(:account_id, :conversation_id)
        end

        def upsert_params
          @upsert_params ||= params.permit(
            :account_id,
            :conversation_id,
            :shopify_order_id,
            :shopify_order_number,
            :last_sync_error,
            order_data_json: {}
          )
        end

        def account
          @account ||= Account.find_by(id: upsert_params[:account_id])
        end

        def conversation
          @conversation ||= account&.conversations&.find_by(id: upsert_params[:conversation_id])
        end

        def serialize(context)
          {
            id: context.id,
            account_id: context.account_id,
            conversation_id: context.conversation_id,
            shopify_order_id: context.shopify_order_id,
            shopify_order_number: context.shopify_order_number,
            order_data_json: context.order_data_json,
            last_synced_at: context.last_synced_at,
            last_sync_error: context.last_sync_error
          }
        end
      end
    end
  end
end
