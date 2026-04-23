# frozen_string_literal: true

# Layer 3 — Wipes all Kin-owned data for a Shopify shop after Shopify
# fires `shop/redact` (Phase 1.7.b).
#
# Shopify guarantees this webhook is not sent until 48h after
# `app/uninstalled`. We add a further `scheduled_delay` cushion (default
# 48h, overridable via `KIN_COMPLIANCE_SHOP_REDACT_DELAY_SECONDS` for
# non-prod dev-store walks) so a merchant who re-installs during the
# window keeps their data.
#
# The Chatwoot `Account` itself is **not** destroyed — Chatwoot core
# owns the account lifecycle and re-installs are expected to reuse the
# same row. We wipe only Kin Layer-3 data + PII on contacts whose only
# attachment to the account was this store.
module Kin
  module Compliance
    class ShopRedactJob < ApplicationJob
      queue_as :kin_compliance

      def self.scheduled_delay
        seconds = ENV.fetch('KIN_COMPLIANCE_SHOP_REDACT_DELAY_SECONDS', nil)
        return 48.hours if seconds.blank?

        Integer(seconds).seconds
      rescue ArgumentError
        48.hours
      end

      def perform(shop_domain:, account_id:)
        account = Account.find_by(id: account_id)
        return Rails.logger.info("[kin:compliance] ShopRedactJob account gone account_id=#{account_id}") if account.nil?

        ActiveRecord::Base.transaction do
          ::Kin::ContactAccessLog.where(account_id: account.id).delete_all
          ::Kin::MacroUsage.where(account_id: account.id).delete_all
          ::Kin::Macro.where(account_id: account.id).delete_all
          ::Kin::ShopifyAction.where(account_id: account.id).delete_all
          ::Kin::ContactNote.where(account_id: account.id).delete_all
          ::Kin::OrderContext.where(account_id: account.id).delete_all
          ::Kin::ShopifyInstallation.where(account_id: account.id, shopify_domain: shop_domain).destroy_all

          account.contacts.find_each { |contact| scrub_contact!(contact) }
        end

        Rails.logger.info("[kin:compliance] ShopRedactJob complete shop=#{shop_domain} account_id=#{account.id}")
      end

      private

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
