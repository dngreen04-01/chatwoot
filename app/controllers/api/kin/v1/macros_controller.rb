# frozen_string_literal: true

# Layer 3 — Kin macros CRUD (Phase 1.6). HMAC-authenticated via
# `Api::Kin::BaseController`. All actions are POST / PATCH so the body
# signature fully covers the request (no query-string scoping), matching
# the 1.4 / 1.5 precedent.
#
# `seed_defaults` is idempotent: it creates the three starter macros
# (WISMO, Returns policy, Discount apology) only when the account has
# zero macros, so the Remix provisioning flow can call it on every install
# without risk of duplicates.
module Api
  module Kin
    module V1
      class MacrosController < BaseController
        DEFAULT_MACROS = [
          {
            name: 'Where is my order',
            category: 'Order status',
            shortcut_key: ';wt',
            channels_json: %w[email chat],
            content: <<~BODY.strip
              Hi {{customer.first_name}},

              Thanks for reaching out. Your order {{order.number}} shipped on
              {{order.shipped_at}} via {{order.carrier}} and you can follow it
              here: {{order.tracking_url}}.

              Let me know if anything else comes up.
            BODY
          },
          {
            name: 'Returns policy',
            category: 'Returns',
            shortcut_key: ';rp',
            channels_json: %w[email chat],
            content: <<~BODY.strip
              Hi {{customer.first_name}},

              Happy to help with a return. We accept returns within 30 days of
              delivery for unused items in original packaging. Reply here with
              the order number and reason and I'll start the process for you.
            BODY
          },
          {
            name: 'Discount apology',
            category: 'Apologies',
            shortcut_key: ';da',
            channels_json: %w[email chat],
            auto_apply_json: { 'tags' => ['apology'] },
            content: <<~BODY.strip
              Hi {{customer.first_name}},

              I'm sorry for the trouble with order {{order.number}}. To make
              it right I've added a 15% discount to your account on your next
              order — use code SORRY15 at checkout. Thanks for bearing with us.
            BODY
          }
        ].freeze

        def list
          return render(json: { error: 'account_not_found' }, status: :not_found) if account.nil?

          scope = ::Kin::Macro.where(account_id: account.id)
          scope = scope.for_category(list_params[:category]) if list_params[:category].present?

          render json: { data: scope.recent_first.map { |record| serialize(record) } }
        end

        def create
          return render(json: { error: 'account_not_found' }, status: :not_found) if account.nil?

          record = ::Kin::Macro.new(macro_attributes.merge(account_id: account.id))
          record.created_by_id = resolved_created_by_id

          if record.save
            render json: serialize(record), status: :created
          else
            render json: { errors: record.errors.full_messages }, status: :unprocessable_entity
          end
        end

        def update
          return render(json: { error: 'account_not_found' }, status: :not_found) if account.nil?
          return render(json: { error: 'macro_not_found' }, status: :not_found) if record.nil?

          if record.update(macro_attributes)
            render json: serialize(record)
          else
            render json: { errors: record.errors.full_messages }, status: :unprocessable_entity
          end
        end

        def destroy
          return render(json: { error: 'account_not_found' }, status: :not_found) if account.nil?
          return render(json: { error: 'macro_not_found' }, status: :not_found) if record.nil?

          record.destroy!
          head :no_content
        end

        def duplicate
          return render(json: { error: 'account_not_found' }, status: :not_found) if account.nil?
          return render(json: { error: 'macro_not_found' }, status: :not_found) if record.nil?

          copy_name = unique_copy_name(record.name)
          copy = ::Kin::Macro.create!(
            account_id: account.id,
            name: copy_name,
            content: record.content,
            category: record.category,
            channels_json: record.channels_json,
            shortcut_key: nil,
            auto_apply_json: record.auto_apply_json || {},
            created_by_id: resolved_created_by_id || record.created_by_id
          )
          render json: serialize(copy), status: :created
        end

        def seed_defaults
          return render(json: { error: 'account_not_found' }, status: :not_found) if account.nil?

          if ::Kin::Macro.where(account_id: account.id).exists?
            return render json: { data: [], seeded: false }
          end

          created = DEFAULT_MACROS.map do |attrs|
            ::Kin::Macro.create!(attrs.merge(account_id: account.id))
          end

          render json: { data: created.map { |r| serialize(r) }, seeded: true }, status: :created
        end

        private

        def account
          @account ||= Account.find_by(id: permitted_account_id)
        end

        def record
          @record ||= ::Kin::Macro.where(account_id: account.id).find_by(id: params[:id])
        end

        def permitted_account_id
          params[:account_id] || macro_params[:account_id] || list_params[:account_id]
        end

        def macro_params
          @macro_params ||= params.permit(
            :account_id,
            :name,
            :content,
            :category,
            :shortcut_key,
            :created_by_id,
            channels_json: [],
            auto_apply_json: {}
          )
        end

        def list_params
          @list_params ||= params.permit(:account_id, :category)
        end

        def macro_attributes
          attrs = macro_params.to_h.slice(
            'name', 'content', 'category', 'shortcut_key', 'channels_json', 'auto_apply_json'
          )
          attrs['channels_json'] = Array(attrs['channels_json']) if attrs.key?('channels_json')
          attrs['auto_apply_json'] ||= {} if attrs.key?('auto_apply_json')
          attrs
        end

        def resolved_created_by_id
          id = macro_params[:created_by_id]
          return nil if id.blank?

          account.users.find_by(id: id)&.id
        end

        def unique_copy_name(base)
          candidate = "#{base} (copy)"
          suffix = 1
          while ::Kin::Macro.where(account_id: account.id, name: candidate).exists?
            suffix += 1
            candidate = "#{base} (copy #{suffix})"
          end
          candidate
        end

        def serialize(record)
          {
            id: record.id,
            account_id: record.account_id,
            name: record.name,
            content: record.content,
            category: record.category,
            channels_json: record.channels_json,
            shortcut_key: record.shortcut_key,
            usage_count: record.usage_count,
            last_used_at: record.last_used_at,
            auto_apply_json: record.auto_apply_json,
            created_by_id: record.created_by_id,
            created_at: record.created_at,
            updated_at: record.updated_at
          }
        end
      end
    end
  end
end
