# frozen_string_literal: true

# Layer 3 — Kin Shopify-actions audit log (Phase 1.5). Append-only,
# HMAC-authenticated via `Api::Kin::BaseController`. One row per agent-
# initiated Shopify mutation (refund / cancel / edit shipping /
# duplicate). The Shopify app itself dispatches the GraphQL mutation
# against the merchant's store; this endpoint records what happened.
#
# All actions are POST so the HMAC body signature covers the whole
# request (consistent with the 1.4 order_contexts + contact_notes
# pattern).
module Api
  module Kin
    module V1
      class ShopifyActionsController < BaseController
        def create
          return render(json: { error: 'account_not_found' }, status: :not_found) if account.nil?
          return render(json: { error: 'agent_not_found' }, status: :not_found) if agent.nil?

          record = ::Kin::ShopifyAction.new(
            account_id: account.id,
            agent_id: agent.id,
            conversation_id: conversation&.id,
            action_name: mutation_params[:action_name],
            shopify_order_id: mutation_params[:shopify_order_id],
            shopify_order_number: mutation_params[:shopify_order_number],
            payload_json: mutation_params[:payload_json] || {},
            result_json: mutation_params[:result_json] || {},
            status: mutation_params[:status],
            error_message: mutation_params[:error_message],
            executed_at: parse_executed_at
          )

          if record.save
            render json: serialize(record), status: :created
          else
            render json: { errors: record.errors.full_messages }, status: :unprocessable_entity
          end
        end

        def list
          return render(json: { error: 'account_not_found' }, status: :not_found) if account.nil?

          scope = ::Kin::ShopifyAction.where(account_id: account.id)
          scope = scope.for_conversation(list_params[:conversation_id]) if list_params[:conversation_id].present?
          limit = [list_params[:limit].to_i.positive? ? list_params[:limit].to_i : 50, 200].min

          records = scope.recent.limit(limit)
          render json: { data: records.map { |r| serialize(r) } }
        end

        private

        def mutation_params
          @mutation_params ||= params.permit(
            :account_id,
            :agent_id,
            :conversation_id,
            :action_name,
            :shopify_order_id,
            :shopify_order_number,
            :status,
            :error_message,
            :executed_at,
            payload_json: {},
            result_json: {}
          )
        end

        def list_params
          @list_params ||= params.permit(:account_id, :conversation_id, :limit)
        end

        def account
          @account ||= Account.find_by(id: mutation_params[:account_id] || list_params[:account_id])
        end

        def agent
          @agent ||= account&.users&.find_by(id: mutation_params[:agent_id])
        end

        def conversation
          return nil if mutation_params[:conversation_id].blank?

          @conversation ||= account&.conversations&.find_by(id: mutation_params[:conversation_id])
        end

        def parse_executed_at
          raw = mutation_params[:executed_at]
          return Time.current if raw.blank?

          Time.zone.parse(raw.to_s) || Time.current
        rescue ArgumentError
          Time.current
        end

        def serialize(record)
          {
            id: record.id,
            account_id: record.account_id,
            agent_id: record.agent_id,
            conversation_id: record.conversation_id,
            action_name: record.action_name,
            shopify_order_id: record.shopify_order_id,
            shopify_order_number: record.shopify_order_number,
            payload_json: record.payload_json,
            result_json: record.result_json,
            status: record.status,
            error_message: record.error_message,
            executed_at: record.executed_at,
            created_at: record.created_at
          }
        end
      end
    end
  end
end
