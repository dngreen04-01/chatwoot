# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Kin::ContactNote do
  it { is_expected.to belong_to(:account) }
  it { is_expected.to belong_to(:contact) }
  it { is_expected.to belong_to(:author).class_name('User') }
  it { is_expected.to validate_presence_of(:body) }
  it { is_expected.to validate_length_of(:body).is_at_most(10_000) }

  describe '.ordered' do
    it 'sorts pinned rows first, then by created_at desc' do
      account = create(:account)
      contact = create(:contact, :with_email, account: account)

      older_plain = create(:kin_contact_note, account: account, contact: contact, created_at: 3.days.ago)
      newer_plain = create(:kin_contact_note, account: account, contact: contact, created_at: 1.day.ago)
      pinned = create(:kin_contact_note, account: account, contact: contact, pinned_at: 1.hour.ago, created_at: 5.days.ago)

      expect(described_class.ordered.to_a).to eq([pinned, newer_plain, older_plain])
    end
  end
end
