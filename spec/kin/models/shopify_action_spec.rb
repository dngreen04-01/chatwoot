# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Kin::ShopifyAction, type: :model do
  describe 'validations' do
    it 'rejects unknown action_name' do
      record = build(:kin_shopify_action, action_name: 'mystery')
      expect(record).not_to be_valid
      expect(record.errors[:action_name]).to be_present
    end

    it 'rejects unknown status' do
      record = build(:kin_shopify_action, status: 'pending')
      expect(record).not_to be_valid
      expect(record.errors[:status]).to be_present
    end

    it 'requires executed_at' do
      record = build(:kin_shopify_action, executed_at: nil)
      expect(record).not_to be_valid
      expect(record.errors[:executed_at]).to be_present
    end

    it 'accepts all whitelisted action_name values' do
      described_class::ACTIONS.each do |name|
        record = build(:kin_shopify_action, action_name: name)
        expect(record).to be_valid, "expected #{name} to be valid"
      end
    end
  end

  describe '.recent' do
    it 'orders by executed_at descending' do
      account = create(:account)
      agent = create(:user, account: account, role: :agent)
      older = create(:kin_shopify_action, account: account, agent: agent, executed_at: 1.day.ago)
      newer = create(:kin_shopify_action, account: account, agent: agent, executed_at: 1.hour.ago)

      expect(described_class.recent.pluck(:id)).to eq([newer.id, older.id])
    end
  end
end
