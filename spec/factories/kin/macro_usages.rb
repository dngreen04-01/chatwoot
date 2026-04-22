# frozen_string_literal: true

FactoryBot.define do
  factory :kin_macro_usage, class: 'Kin::MacroUsage' do
    association :account
    macro { association :kin_macro, account: account }
    agent { association :user, account: account, role: :agent }
    conversation { nil }
    used_at { Time.current }
  end
end
