# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Kin::OrderContext do
  it { is_expected.to belong_to(:account) }
  it { is_expected.to belong_to(:conversation) }
  it { is_expected.to validate_presence_of(:last_synced_at) }

  it 'enforces one row per (account, conversation)' do
    existing = create(:kin_order_context)
    duplicate = build(
      :kin_order_context,
      account: existing.account,
      conversation: existing.conversation
    )
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:account_id]).to include('has already been taken')
  end

  describe '.stale' do
    it 'returns rows whose last_synced_at is older than the ttl' do
      fresh = create(:kin_order_context, last_synced_at: 1.minute.ago)
      stale = create(:kin_order_context, last_synced_at: 30.minutes.ago)

      expect(described_class.stale(15.minutes)).to include(stale)
      expect(described_class.stale(15.minutes)).not_to include(fresh)
    end
  end
end
