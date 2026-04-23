# frozen_string_literal: true

FactoryBot.define do
  factory :kin_contact_access_log, class: 'Kin::ContactAccessLog' do
    association :account
    agent { association :user, account: account, role: :agent }
    contact { nil }
    conversation { nil }
    action { 'show' }
    accessed_at { Time.current }
    ip_address { '127.0.0.1' }
    user_agent { 'RSpec' }
  end
end
