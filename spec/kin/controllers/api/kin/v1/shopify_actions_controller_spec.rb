# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::Kin::V1::ShopifyActionsController, type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:contact) { create(:contact, :with_email, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:shared_secret) { 'kin-test-shared-secret' }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('KIN_INSTALLATION_SHARED_SECRET', nil).and_return(shared_secret)
    allow(::Redis::Alfred).to receive(:set).and_return(true)
  end

  def signed_post(path, body_hash, secret: shared_secret, verb: :post)
    body = body_hash.to_json
    ts = Time.current.to_i.to_s
    signature = OpenSSL::HMAC.hexdigest('SHA256', secret, "#{ts}.#{body}")

    send(verb, path,
         params: body,
         headers: {
           'CONTENT_TYPE' => 'application/json',
           'X-Kin-Timestamp' => ts,
           'X-Kin-Signature' => "v1=#{signature}"
         })
  end

  describe 'POST /api/kin/v1/shopify_actions' do
    let(:base_payload) do
      {
        account_id: account.id,
        agent_id: agent.id,
        conversation_id: conversation.id,
        action_name: 'refund',
        shopify_order_id: 'gid://shopify/Order/9001',
        shopify_order_number: '#K-9001',
        payload_json: { 'lineItems' => [{ 'lineItemId' => 'gid://shopify/LineItem/1', 'quantity' => 1 }] },
        result_json: { 'refund' => { 'id' => 'gid://shopify/Refund/100' } },
        status: 'succeeded'
      }
    end

    it 'appends a succeeded audit row' do
      expect { signed_post('/api/kin/v1/shopify_actions', base_payload) }
        .to change(::Kin::ShopifyAction, :count).by(1)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['status']).to eq('succeeded')
      expect(body['action_name']).to eq('refund')
      expect(body['payload_json']).to be_a(Hash)
    end

    it 'records a failed action with an error_message' do
      signed_post('/api/kin/v1/shopify_actions', base_payload.merge(
                                                    status: 'failed',
                                                    result_json: {},
                                                    error_message: 'Transactions exceed order total'
                                                  ))

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['status']).to eq('failed')
      expect(response.parsed_body['error_message']).to eq('Transactions exceed order total')
    end

    it 'rejects unknown action_name values' do
      signed_post('/api/kin/v1/shopify_actions', base_payload.merge(action_name: 'burn_store'))

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rejects unknown status values' do
      signed_post('/api/kin/v1/shopify_actions', base_payload.merge(status: 'maybe'))

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns 404 when the agent is not on the account' do
      foreign_agent = create(:user, account: other_account, role: :agent)

      signed_post('/api/kin/v1/shopify_actions', base_payload.merge(agent_id: foreign_agent.id))

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq('agent_not_found')
    end

    it 'allows a null conversation_id' do
      signed_post('/api/kin/v1/shopify_actions', base_payload.merge(conversation_id: nil))

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['conversation_id']).to be_nil
    end

    it 'nullifies conversation_id when the conversation belongs to another account' do
      foreign_conv = create(:conversation)

      signed_post('/api/kin/v1/shopify_actions', base_payload.merge(conversation_id: foreign_conv.id))

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['conversation_id']).to be_nil
    end

    it 'rejects unsigned requests with 401' do
      post '/api/kin/v1/shopify_actions',
           params: base_payload.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/kin/v1/shopify_actions/list' do
    it 'returns recent actions for the account in descending executed_at order' do
      older = create(:kin_shopify_action, account: account, agent: agent, executed_at: 2.hours.ago)
      newer = create(:kin_shopify_action, account: account, agent: agent, executed_at: 10.minutes.ago)

      signed_post('/api/kin/v1/shopify_actions/list', { account_id: account.id })

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['data'].map { |row| row['id'] }
      expect(ids).to eq([newer.id, older.id])
    end

    it 'filters by conversation_id when provided' do
      scoped = create(:kin_shopify_action, account: account, agent: agent, conversation: conversation)
      _unscoped = create(:kin_shopify_action, account: account, agent: agent, conversation: nil)

      signed_post('/api/kin/v1/shopify_actions/list',
                  { account_id: account.id, conversation_id: conversation.id })

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['data'].map { |row| row['id'] }
      expect(ids).to eq([scoped.id])
    end

    it 'isolates across accounts' do
      create(:kin_shopify_action, account: account, agent: agent)

      signed_post('/api/kin/v1/shopify_actions/list', { account_id: other_account.id })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['data']).to eq([])
    end
  end
end
