# frozen_string_literal: true

# Layer 3 — Kin macro usage log (Phase 1.6). Writes one row per
# macro-backed reply and transactionally bumps the parent macro's
# `usage_count` + `last_used_at`. List endpoint returns the raw rows plus
# an aggregated `daily_counts` array for the trailing 30 days to power
# the detail-pane bar chart.
module Api
  module Kin
    module V1
      class MacroUsagesController < BaseController
        def create
          return render(json: { error: 'account_not_found' }, status: :not_found) if account.nil?
          return render(json: { error: 'agent_not_found' }, status: :not_found) if agent.nil?
          return render(json: { error: 'macro_not_found' }, status: :not_found) if macro.nil?

          used_at = parse_used_at
          usage = nil

          ActiveRecord::Base.transaction do
            usage = ::Kin::MacroUsage.create!(
              macro_id: macro.id,
              account_id: account.id,
              agent_id: agent.id,
              conversation_id: scoped_conversation&.id,
              used_at: used_at
            )
            macro.update!(usage_count: macro.usage_count + 1, last_used_at: used_at)
          end

          render json: serialize(usage), status: :created
        end

        def list
          return render(json: { error: 'account_not_found' }, status: :not_found) if account.nil?

          scope = ::Kin::MacroUsage.where(account_id: account.id)
          scope = scope.where(macro_id: list_params[:macro_id]) if list_params[:macro_id].present?
          limit = [list_params[:limit].to_i.positive? ? list_params[:limit].to_i : 100, 500].min

          records = scope.recent_first.limit(limit)

          render json: {
            data: records.map { |record| serialize(record) },
            daily_counts: daily_counts_for(scope)
          }
        end

        private

        def account
          @account ||= Account.find_by(id: usage_params[:account_id] || list_params[:account_id])
        end

        def agent
          @agent ||= account&.users&.find_by(id: usage_params[:agent_id])
        end

        def macro
          @macro ||= ::Kin::Macro.where(account_id: account.id).find_by(id: usage_params[:macro_id])
        end

        def scoped_conversation
          return nil if usage_params[:conversation_id].blank?

          @scoped_conversation ||= account.conversations.find_by(id: usage_params[:conversation_id])
        end

        def usage_params
          @usage_params ||= params.permit(:account_id, :agent_id, :macro_id, :conversation_id, :used_at)
        end

        def list_params
          @list_params ||= params.permit(:account_id, :macro_id, :limit)
        end

        def parse_used_at
          raw = usage_params[:used_at]
          return Time.current if raw.blank?

          Time.zone.parse(raw.to_s) || Time.current
        rescue ArgumentError
          Time.current
        end

        # Returns `[{ date: 'YYYY-MM-DD', count: N }, ...]` for the trailing
        # 30 days ending today. Days with zero usage are included so the UI
        # can render a contiguous 30-bar chart without frontend gap-filling.
        def daily_counts_for(scope)
          today = Time.zone.today
          window_start = today - 29.days
          counts_by_date = scope.where('used_at >= ?', window_start.beginning_of_day)
                                .group("date_trunc('day', used_at)")
                                .count
                                .transform_keys(&:to_date)

          (window_start..today).map do |date|
            { date: date.iso8601, count: counts_by_date[date] || 0 }
          end
        end

        def serialize(record)
          {
            id: record.id,
            macro_id: record.macro_id,
            account_id: record.account_id,
            agent_id: record.agent_id,
            conversation_id: record.conversation_id,
            used_at: record.used_at,
            created_at: record.created_at
          }
        end
      end
    end
  end
end
