# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Kin::MacroUsage, type: :model do
  describe 'validations' do
    it 'requires used_at' do
      record = build(:kin_macro_usage, used_at: nil)
      expect(record).not_to be_valid
      expect(record.errors[:used_at]).to be_present
    end
  end

  describe '.trailing_30_days' do
    it 'excludes rows older than 30 days' do
      macro = create(:kin_macro)
      fresh = create(:kin_macro_usage, macro: macro, account: macro.account, used_at: 5.days.ago)
      create(:kin_macro_usage, macro: macro, account: macro.account, used_at: 45.days.ago)

      expect(described_class.trailing_30_days.pluck(:id)).to eq([fresh.id])
    end
  end
end
