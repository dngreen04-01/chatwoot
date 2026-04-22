# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::Kin::V1::MacroUsagesController, type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:contact) { create(:contact, :with_email, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:macro) { create(:kin_macro, account: account) }
  let(:shared_secret) { 'kin-test-shared-secret' }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('KIN_INSTALLATION_SHARED_SECRET', nil).and_return(shared_secret)
    allow(::Redis::Alfred).to receive(:set).and_return(true)
  end

  def signed_post(path, body_hash, secret: shared_secret)
    body = body_hash.to_json
    ts = Time.current.to_i.to_s
    signature = OpenSSL::HMAC.hexdigest('SHA256', secret, "#{ts}.#{body}")

    post path,
         params: body,
         headers: {
           'CONTENT_TYPE' => 'application/json',
           'X-Kin-Timestamp' => ts,
           'X-Kin-Signature' => "v1=#{signature}"
         }
  end

  describe 'POST /api/kin/v1/macro_usages' do
    let(:base_payload) do
      {
        account_id: account.id,
        agent_id: agent.id,
        macro_id: macro.id,
        conversation_id: conversation.id
      }
    end

    it 'appends a usage row and bumps the parent macro counters' do
      expect {
        signed_post('/api/kin/v1/macro_usages', base_payload)
      }.to change(::Kin::MacroUsage, :count).by(1)

      expect(response).to have_http_status(:created)
      macro.reload
      expect(macro.usage_count).to eq(1)
      expect(macro.last_used_at).to be_within(5.seconds).of(Time.current)
    end

    it '404s when the macro belongs to another account' do
      foreign_macro = create(:kin_macro, account: other_account)

      signed_post('/api/kin/v1/macro_usages', base_payload.merge(macro_id: foreign_macro.id))

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq('macro_not_found')
    end

    it '404s when the agent is not on the account' do
      foreign_agent = create(:user, account: other_account, role: :agent)

      signed_post('/api/kin/v1/macro_usages', base_payload.merge(agent_id: foreign_agent.id))

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq('agent_not_found')
    end
  end

  describe 'POST /api/kin/v1/macro_usages/list' do
    it 'returns usages + 30-day daily counts' do
      create(:kin_macro_usage, macro: macro, account: account, agent: agent, used_at: 2.days.ago)
      create(:kin_macro_usage, macro: macro, account: account, agent: agent, used_at: 2.days.ago)
      create(:kin_macro_usage, macro: macro, account: account, agent: agent, used_at: 10.days.ago)

      signed_post('/api/kin/v1/macro_usages/list',
                  { account_id: account.id, macro_id: macro.id })

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['data'].size).to eq(3)
      expect(body['daily_counts'].size).to eq(30)

      two_days_ago = (Time.zone.today - 2.days).iso8601
      ten_days_ago = (Time.zone.today - 10.days).iso8601
      expect(body['daily_counts'].find { |d| d['date'] == two_days_ago }['count']).to eq(2)
      expect(body['daily_counts'].find { |d| d['date'] == ten_days_ago }['count']).to eq(1)
    end

    it 'scopes to the requested macro' do
      other_macro = create(:kin_macro, account: account, name: 'Other')
      create(:kin_macro_usage, macro: macro, account: account, agent: agent)
      create(:kin_macro_usage, macro: other_macro, account: account, agent: agent)

      signed_post('/api/kin/v1/macro_usages/list',
                  { account_id: account.id, macro_id: macro.id })

      expect(response.parsed_body['data'].size).to eq(1)
    end
  end
end
