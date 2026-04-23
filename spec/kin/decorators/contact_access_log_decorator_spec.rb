# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Kin::ContactAccessLogDecorator, type: :request do
  let(:account) { create(:account) }
  # Use administrator to bypass per-conversation Pundit assignee checks
  # in the conversation spec below — this test exercises the decorator,
  # not authorization policy.
  let(:agent) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }

  describe 'Api::V1::Accounts::ContactsController#show' do
    it 'writes one access log row per successful show' do
      expect do
        get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
            headers: agent.create_new_auth_token,
            as: :json
      end.to change(Kin::ContactAccessLog, :count).by(1)

      expect(response).to have_http_status(:ok)
      log = Kin::ContactAccessLog.order(:id).last
      expect(log.account_id).to eq(account.id)
      expect(log.agent_id).to eq(agent.id)
      expect(log.contact_id).to eq(contact.id)
      expect(log.conversation_id).to be_nil
      expect(log.action).to eq('show')
    end

    it 'does not 500 when the log write raises' do
      allow(Kin::ContactAccessLog).to receive(:bulk_log).and_raise(StandardError, 'db down')

      expect do
        get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
            headers: agent.create_new_auth_token,
            as: :json
      end.not_to change(Kin::ContactAccessLog, :count)

      expect(response).to have_http_status(:ok)
    end

    it 'does not leak logs across accounts on a denied request' do
      other_account = create(:account)
      other_contact = create(:contact, account: other_account)

      expect do
        get "/api/v1/accounts/#{other_account.id}/contacts/#{other_contact.id}",
            headers: agent.create_new_auth_token,
            as: :json
      end.not_to change(Kin::ContactAccessLog, :count)

      expect(response).not_to have_http_status(:ok)
    end
  end

  describe 'Api::V1::Accounts::ConversationsController#show' do
    let(:inbox) { create(:inbox, account: account) }
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
    let(:conversation) { create(:conversation, account: account, contact: contact, contact_inbox: contact_inbox, inbox: inbox) }

    it 'writes one access log row per successful show' do
      expect do
        get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}",
            headers: agent.create_new_auth_token,
            as: :json
      end.to change(Kin::ContactAccessLog, :count).by(1)

      expect(response).to have_http_status(:ok)
      log = Kin::ContactAccessLog.order(:id).last
      expect(log.account_id).to eq(account.id)
      expect(log.agent_id).to eq(agent.id)
      expect(log.conversation_id).to eq(conversation.id)
      expect(log.contact_id).to eq(contact.id)
      expect(log.action).to eq('show')
    end
  end
end
