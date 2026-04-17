# frozen_string_literal: true

FactoryBot.define do
  factory :kin_shopify_installation, class: 'Kin::ShopifyInstallation' do
    association :account
    sequence(:shopify_domain) { |n| "kin-test-#{n}.myshopify.com" }
    shopify_access_token { 'shpat_test_token' }
    shopify_store_name { 'Kin Test Store' }
    scopes { 'read_orders,read_customers' }
    installed_at { Time.current }
  end
end
