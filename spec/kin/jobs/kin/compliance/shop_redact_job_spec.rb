# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Kin::Compliance::ShopRedactJob, type: :job do
  let(:account) { create(:account) }
  let(:shop_domain) { 'kin-redact-spec.myshopify.com' }
  let!(:installation) { create(:kin_shopify_installation, account: account, shopify_domain: shop_domain) }

  describe '.scheduled_delay' do
    it 'defaults to 48 hours' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('KIN_COMPLIANCE_SHOP_REDACT_DELAY_SECONDS', nil).and_return(nil)

      expect(described_class.scheduled_delay).to eq(48.hours)
    end

    it 'reads KIN_COMPLIANCE_SHOP_REDACT_DELAY_SECONDS when present' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('KIN_COMPLIANCE_SHOP_REDACT_DELAY_SECONDS', nil).and_return('30')

      expect(described_class.scheduled_delay).to eq(30.seconds)
    end

    it 'falls back to 48 hours on a non-integer override' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('KIN_COMPLIANCE_SHOP_REDACT_DELAY_SECONDS', nil).and_return('soon')

      expect(described_class.scheduled_delay).to eq(48.hours)
    end
  end

  describe '#perform' do
    it 'wipes Kin Layer-3 data and scrubs contact PII' do
      contact = create(:contact,
                       account: account,
                       name: 'Lena Merchant',
                       email: 'lena@example.com',
                       phone_number: '+64211111111')
      create(:kin_contact_note, account: account, contact: contact)
      create(:kin_order_context, account: account) if defined?(FactoryBot.factories[:kin_order_context])

      described_class.new.perform(shop_domain: shop_domain, account_id: account.id)

      expect(::Kin::ShopifyInstallation.where(account_id: account.id, shopify_domain: shop_domain)).to be_empty
      expect(::Kin::ContactNote.where(account_id: account.id)).to be_empty

      contact.reload
      expect(contact.name).to eq('[redacted]')
      expect(contact.email).to be_nil
      expect(contact.phone_number).to be_nil
    end

    it 'no-ops when the account has been deleted' do
      expect { described_class.new.perform(shop_domain: shop_domain, account_id: 0) }.not_to raise_error
    end
  end
end
