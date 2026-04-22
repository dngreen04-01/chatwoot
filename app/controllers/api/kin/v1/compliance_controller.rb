# frozen_string_literal: true

# Layer 3 — Shopify mandatory privacy webhooks (Phase 1.7.b).
#
# Shopify delivers `customers/data_request`, `customers/redact`, and
# `shop/redact` to the Kin Shopify app (Remix). The Remix handler
# verifies the Shopify `X-Shopify-Hmac-SHA256` header (via
# `authenticate.webhook`) and then forwards the payload to this
# controller signed with the internal Kin HMAC. This separation keeps
# the Shopify webhook secret on the Remix side only.
#
# Compliance rules (BFS App Store review blocker):
#   - Invalid inner HMAC → 401 (handled by Api::Kin::BaseController).
#   - Invalid payload → 422 (never silent 200; Shopify will redeliver).
#   - Valid payload → 200 + mutation.
module Api
  module Kin
    module V1
      class ComplianceController < BaseController
        # POST /api/kin/v1/compliance/customer_redact
        #
        # Scrubs PII from the matching Contact but keeps the row so the
        # merchant's conversation history stays intact (Shopify's spec
        # only requires PII erasure, not full deletion).
        def customer_redact
          return render(json: { error: 'shop_domain_required' }, status: :unprocessable_entity) if shop_domain.blank?
          return render(json: { error: 'shop_not_installed' }, status: :not_found) if account.nil?

          ActiveRecord::Base.transaction do
            # Materialize the matching contact IDs up front; we need them
            # after scrubbing strips the email/phone the match was built
            # on, so a lazy subquery would resolve to the empty set.
            contact_ids = matching_contacts.pluck(:id)
            next if contact_ids.empty?

            ::Kin::ContactNote.where(account_id: account.id, contact_id: contact_ids).destroy_all
            Contact.where(id: contact_ids).find_each { |contact| scrub_contact!(contact) }
          end

          render json: { ok: true }
        end

        # POST /api/kin/v1/compliance/customer_data_request
        #
        # Shopify requires a 200 ack on receipt. The merchant is
        # responsible for fulfilling the export — we log the payload so
        # an operator can surface it through the support flow. Auto-
        # generating the export is a Phase 2 follow-up.
        def customer_data_request
          return render(json: { error: 'shop_domain_required' }, status: :unprocessable_entity) if shop_domain.blank?

          Rails.logger.info(
            '[kin:compliance] customer_data_request received ' \
            "shop=#{shop_domain} customer=#{params[:customer].is_a?(ActionController::Parameters) ? params.dig(:customer, :id) : nil}"
          )

          render json: { ok: true }
        end

        # POST /api/kin/v1/compliance/shop_redact
        #
        # Fired 48h after `app/uninstalled`. We schedule the sweep with
        # an additional 48h cushion so a merchant who reinstalls inside
        # the redact grace window still has their data. In non-prod
        # environments the cushion is compressed via
        # `KIN_COMPLIANCE_SHOP_REDACT_DELAY_SECONDS` to keep the
        # dev-store walk tractable.
        def shop_redact
          return render(json: { error: 'shop_domain_required' }, status: :unprocessable_entity) if shop_domain.blank?

          if account.present?
            delay = ::Kin::Compliance::ShopRedactJob.scheduled_delay
            ::Kin::Compliance::ShopRedactJob
              .set(wait: delay)
              .perform_later(shop_domain: shop_domain, account_id: account.id)
          else
            Rails.logger.info("[kin:compliance] shop_redact for unknown shop_domain=#{shop_domain}; no-op")
          end

          render json: { ok: true }
        end

        private

        def shop_domain
          @shop_domain ||= params[:shop_domain].presence || params[:shop].presence
        end

        def installation
          @installation ||= ::Kin::ShopifyInstallation.find_by(shopify_domain: shop_domain)
        end

        def account
          @account ||= installation&.account
        end

        # Shopify identifies the redact target by any of (email, phone,
        # id). We match on email + phone; id is Shopify-side and not
        # cross-referenced in Chatwoot.
        def matching_contacts
          scope = account.contacts.none
          customer = params[:customer]
          return scope unless customer.is_a?(ActionController::Parameters) || customer.is_a?(Hash)

          email = customer[:email].presence
          phone = customer[:phone].presence

          conditions = []
          conditions << account.contacts.where('LOWER(email) = ?', email.to_s.downcase) if email
          conditions << account.contacts.where(phone_number: phone) if phone
          return scope if conditions.empty?

          conditions.reduce { |acc, rel| acc.or(rel) }
        end

        def scrub_contact!(contact)
          contact.update!(
            name: '[redacted]',
            email: nil,
            phone_number: nil,
            identifier: nil,
            additional_attributes: {},
            custom_attributes: {}
          )
        end
      end
    end
  end
end
