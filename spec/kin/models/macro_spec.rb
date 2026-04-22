# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Kin::Macro, type: :model do
  describe 'validations' do
    it 'requires name, content, and category' do
      record = described_class.new(account: create(:account))
      expect(record).not_to be_valid
      expect(record.errors[:name]).to be_present
      expect(record.errors[:content]).to be_present
    end

    it 'enforces name uniqueness scoped to account' do
      account = create(:account)
      create(:kin_macro, account: account, name: 'WISMO')
      duplicate = build(:kin_macro, account: account, name: 'wismo')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to be_present
    end

    it 'allows the same name across different accounts' do
      create(:kin_macro, account: create(:account), name: 'WISMO')
      other = build(:kin_macro, account: create(:account), name: 'WISMO')

      expect(other).to be_valid
    end
  end

  describe 'usages association' do
    it 'cascades destroy to usage rows' do
      macro = create(:kin_macro)
      create(:kin_macro_usage, macro: macro, account: macro.account)

      expect { macro.destroy! }.to change(Kin::MacroUsage, :count).by(-1)
    end
  end
end
