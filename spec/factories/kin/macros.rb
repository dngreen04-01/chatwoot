# frozen_string_literal: true

FactoryBot.define do
  factory :kin_macro, class: 'Kin::Macro' do
    association :account
    sequence(:name) { |n| "WISMO reply #{n}" }
    content { "Hi {{customer.first_name}}, your order {{order.number}} is on its way: {{order.tracking_url}}." }
    category { 'Order status' }
    channels_json { %w[email chat] }
    auto_apply_json { {} }
    shortcut_key { nil }
  end
end
