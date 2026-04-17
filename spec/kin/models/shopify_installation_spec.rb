# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Kin::ShopifyInstallation do
  it { is_expected.to belong_to(:account) }
  it { is_expected.to validate_presence_of(:shopify_domain) }
  it { is_expected.to validate_presence_of(:shopify_access_token) }

  it 'enforces unique shopify_domain' do
    existing = create(:kin_shopify_installation, shopify_domain: 'unique-shop.myshopify.com')
    duplicate = build(:kin_shopify_installation, shopify_domain: existing.shopify_domain)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:shopify_domain]).to include('has already been taken')
  end

  it_behaves_like 'encrypted external credential',
                  factory: :kin_shopify_installation,
                  attribute: :shopify_access_token,
                  value: 'shpat_super_secret_ABC123'
end
