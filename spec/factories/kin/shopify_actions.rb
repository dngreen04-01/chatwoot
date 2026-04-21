# frozen_string_literal: true

FactoryBot.define do
  factory :kin_shopify_action, class: 'Kin::ShopifyAction' do
    association :account
    agent { association :user, account: account, role: :agent }
    conversation { nil }
    action_name { 'refund' }
    shopify_order_id { 'gid://shopify/Order/5123456789012' }
    shopify_order_number { '#K-1001' }
    payload_json { { 'amount' => '12.00', 'currencyCode' => 'USD' } }
    result_json { { 'refund_id' => 'gid://shopify/Refund/1' } }
    status { 'succeeded' }
    error_message { nil }
    executed_at { Time.current }
  end
end
