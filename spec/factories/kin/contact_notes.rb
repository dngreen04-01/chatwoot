# frozen_string_literal: true

FactoryBot.define do
  factory :kin_contact_note, class: 'Kin::ContactNote' do
    association :account
    contact { association :contact, :with_email, account: account }
    author { association :user, account: account, role: :agent }
    body { 'Customer prefers express shipping.' }
    pinned_at { nil }
  end
end
