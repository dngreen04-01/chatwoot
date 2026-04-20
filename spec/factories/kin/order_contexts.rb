# frozen_string_literal: true

FactoryBot.define do
  factory :kin_order_context, class: 'Kin::OrderContext' do
    association :account
    conversation { association :conversation, account: account }
    shopify_order_id { '5123456789012' }
    shopify_order_number { '#K-1001' }
    order_data_json do
      {
        'id' => 'gid://shopify/Order/5123456789012',
        'name' => '#K-1001',
        'displayFinancialStatus' => 'PAID',
        'displayFulfillmentStatus' => 'FULFILLED',
        'totalPriceSet' => { 'shopMoney' => { 'amount' => '129.00', 'currencyCode' => 'USD' } },
        'lineItems' => { 'edges' => [] }
      }
    end
    last_synced_at { Time.current }
  end
end
