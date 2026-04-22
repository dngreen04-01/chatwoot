# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::Kin::V1::MacrosController, type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:shared_secret) { 'kin-test-shared-secret' }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('KIN_INSTALLATION_SHARED_SECRET', nil).and_return(shared_secret)
    allow(::Redis::Alfred).to receive(:set).and_return(true)
  end

  def signed_request(verb, path, body_hash, secret: shared_secret)
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

  describe 'POST /api/kin/v1/macros/list' do
    it 'returns macros for the account, newest updated first' do
      older = create(:kin_macro, account: account, name: 'Older')
      newer = create(:kin_macro, account: account, name: 'Newer', updated_at: 1.minute.from_now)

      signed_request(:post, '/api/kin/v1/macros/list', { account_id: account.id })

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['data'].map { |row| row['id'] }
      expect(ids).to eq([newer.id, older.id])
    end

    it 'filters by category when provided' do
      returns = create(:kin_macro, account: account, category: 'Returns', name: 'Returns A')
      create(:kin_macro, account: account, category: 'Order status', name: 'OS A')

      signed_request(:post, '/api/kin/v1/macros/list',
                     { account_id: account.id, category: 'Returns' })

      expect(response.parsed_body['data'].map { |m| m['id'] }).to eq([returns.id])
    end

    it 'isolates across accounts' do
      create(:kin_macro, account: account)

      signed_request(:post, '/api/kin/v1/macros/list', { account_id: other_account.id })

      expect(response.parsed_body['data']).to eq([])
    end

    it '401s when unsigned' do
      post '/api/kin/v1/macros/list',
           params: { account_id: account.id }.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/kin/v1/macros' do
    let(:payload) do
      {
        account_id: account.id,
        created_by_id: agent.id,
        name: 'Where is my order',
        content: 'Hi {{customer.first_name}}',
        category: 'Order status',
        shortcut_key: ';wt',
        channels_json: %w[email chat],
        auto_apply_json: { 'tags' => ['wismo'] }
      }
    end

    it 'creates a macro' do
      expect { signed_request(:post, '/api/kin/v1/macros', payload) }
        .to change(::Kin::Macro, :count).by(1)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['name']).to eq('Where is my order')
      expect(body['shortcut_key']).to eq(';wt')
      expect(body['auto_apply_json']).to eq('tags' => ['wismo'])
      expect(body['created_by_id']).to eq(agent.id)
    end

    it 'rejects duplicate names within the same account' do
      create(:kin_macro, account: account, name: 'Where is my order')

      signed_request(:post, '/api/kin/v1/macros', payload)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'ignores created_by_id from another account' do
      foreign_agent = create(:user, account: other_account, role: :agent)

      signed_request(:post, '/api/kin/v1/macros', payload.merge(created_by_id: foreign_agent.id))

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['created_by_id']).to be_nil
    end
  end

  describe 'PATCH /api/kin/v1/macros/:id' do
    it 'updates the macro' do
      macro = create(:kin_macro, account: account, name: 'Before')

      signed_request(:patch, "/api/kin/v1/macros/#{macro.id}",
                     { account_id: account.id, name: 'After', content: macro.content })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['name']).to eq('After')
      expect(macro.reload.name).to eq('After')
    end

    it '404s when the macro belongs to another account' do
      macro = create(:kin_macro, account: other_account)

      signed_request(:patch, "/api/kin/v1/macros/#{macro.id}",
                     { account_id: account.id, name: 'Hijack' })

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/kin/v1/macros/:id/destroy' do
    it 'deletes the macro and cascades usages' do
      macro = create(:kin_macro, account: account)
      create(:kin_macro_usage, macro: macro, account: account)

      expect {
        signed_request(:post, "/api/kin/v1/macros/#{macro.id}/destroy",
                       { account_id: account.id })
      }.to change(::Kin::Macro, :count).by(-1)
       .and change(::Kin::MacroUsage, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end

  describe 'POST /api/kin/v1/macros/:id/duplicate' do
    it 'clones the macro with a "(copy)" suffix and clears the shortcut' do
      macro = create(:kin_macro, account: account, name: 'Base', shortcut_key: ';bb')

      expect {
        signed_request(:post, "/api/kin/v1/macros/#{macro.id}/duplicate",
                       { account_id: account.id })
      }.to change(::Kin::Macro, :count).by(1)

      expect(response).to have_http_status(:created)
      clone = response.parsed_body
      expect(clone['name']).to eq('Base (copy)')
      expect(clone['shortcut_key']).to be_nil
    end

    it 'increments the suffix when "(copy)" is taken' do
      create(:kin_macro, account: account, name: 'Base')
      create(:kin_macro, account: account, name: 'Base (copy)')
      source = ::Kin::Macro.find_by(name: 'Base')

      signed_request(:post, "/api/kin/v1/macros/#{source.id}/duplicate",
                     { account_id: account.id })

      expect(response.parsed_body['name']).to eq('Base (copy 2)')
    end
  end

  describe 'POST /api/kin/v1/macros/seed_defaults' do
    it 'creates the three default macros when the account is empty' do
      expect {
        signed_request(:post, '/api/kin/v1/macros/seed_defaults',
                       { account_id: account.id })
      }.to change(::Kin::Macro, :count).by(3)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['seeded']).to be(true)
      names = response.parsed_body['data'].map { |m| m['name'] }
      expect(names).to contain_exactly('Where is my order', 'Returns policy', 'Discount apology')
    end

    it 'is idempotent when macros already exist' do
      create(:kin_macro, account: account)

      expect {
        signed_request(:post, '/api/kin/v1/macros/seed_defaults',
                       { account_id: account.id })
      }.not_to change(::Kin::Macro, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['seeded']).to be(false)
    end
  end
end
