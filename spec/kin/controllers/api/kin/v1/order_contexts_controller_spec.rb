# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::Kin::V1::OrderContextsController, type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
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

  describe 'POST /api/kin/v1/order_contexts/lookup' do
    it 'returns the cached row for a known (account, conversation)' do
      create(
        :kin_order_context,
        account: account,
        conversation: conversation,
        shopify_order_number: '#K-2002'
      )

      signed_post('/api/kin/v1/order_contexts/lookup',
                  { account_id: account.id, conversation_id: conversation.id })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['shopify_order_number']).to eq('#K-2002')
      expect(response.parsed_body['order_data_json']).to be_a(Hash)
    end

    it 'returns {status: "miss"} when no row exists' do
      signed_post('/api/kin/v1/order_contexts/lookup',
                  { account_id: account.id, conversation_id: conversation.id })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('status' => 'miss')
    end

    it 'isolates across accounts' do
      create(:kin_order_context, account: account, conversation: conversation, shopify_order_number: '#K-private')

      signed_post('/api/kin/v1/order_contexts/lookup',
                  { account_id: other_account.id, conversation_id: conversation.id })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('status' => 'miss')
    end

    it 'rejects unsigned requests with 401' do
      post '/api/kin/v1/order_contexts/lookup',
           params: { account_id: account.id, conversation_id: conversation.id }.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/kin/v1/order_contexts/upsert' do
    let(:payload) do
      {
        account_id: account.id,
        conversation_id: conversation.id,
        shopify_order_id: 'gid://shopify/Order/9001',
        shopify_order_number: '#K-9001',
        order_data_json: {
          'displayFinancialStatus' => 'PAID',
          'displayFulfillmentStatus' => 'IN_PROGRESS'
        }
      }
    end

    it 'creates a new cache row and stamps last_synced_at' do
      freeze_time do
        expect { signed_post('/api/kin/v1/order_contexts/upsert', payload) }
          .to change(::Kin::OrderContext, :count).by(1)

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['shopify_order_number']).to eq('#K-9001')
        row = ::Kin::OrderContext.find(body['id'])
        expect(row.last_synced_at).to be_within(1.second).of(Time.current)
      end
    end

    it 'is idempotent on repeated upserts for the same conversation' do
      signed_post('/api/kin/v1/order_contexts/upsert', payload)
      first_id = response.parsed_body['id']

      signed_post('/api/kin/v1/order_contexts/upsert', payload.merge(shopify_order_number: '#K-9001-v2'))
      expect(response.parsed_body['id']).to eq(first_id)
      expect(response.parsed_body['shopify_order_number']).to eq('#K-9001-v2')
      expect(::Kin::OrderContext.count).to eq(1)
    end

    it 'returns 404 when the conversation does not belong to the account' do
      foreign_conversation = create(:conversation)

      signed_post('/api/kin/v1/order_contexts/upsert',
                  payload.merge(conversation_id: foreign_conversation.id))

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq('conversation_not_found')
    end
  end

  describe 'POST /api/kin/v1/order_contexts/destroy' do
    it 'deletes the scoped row and returns 204' do
      create(:kin_order_context, account: account, conversation: conversation)

      signed_post('/api/kin/v1/order_contexts/destroy',
                  { account_id: account.id, conversation_id: conversation.id })

      expect(response).to have_http_status(:no_content)
      expect(::Kin::OrderContext.count).to eq(0)
    end

    it 'is idempotent when the row is already gone' do
      signed_post('/api/kin/v1/order_contexts/destroy',
                  { account_id: account.id, conversation_id: conversation.id })

      expect(response).to have_http_status(:no_content)
    end
  end
end
