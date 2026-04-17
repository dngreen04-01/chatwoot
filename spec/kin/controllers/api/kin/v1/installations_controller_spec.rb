# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::Kin::V1::InstallationsController, type: :request do
  let(:account) { create(:account) }
  let(:shared_secret) { 'kin-test-shared-secret' }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('KIN_INSTALLATION_SHARED_SECRET', nil).and_return(shared_secret)
    # Avoid cross-example nonce collisions from the real Redis replay cache.
    allow(::Redis::Alfred).to receive(:set).and_return(true)
  end

  def signed_post(body_hash, secret: shared_secret, skew: 0, timestamp: nil)
    body = body_hash.to_json
    ts = (timestamp || (Time.current.to_i + skew)).to_s
    signature = OpenSSL::HMAC.hexdigest('SHA256', secret, "#{ts}.#{body}")

    post '/api/kin/v1/installations',
         params: body,
         headers: {
           'CONTENT_TYPE' => 'application/json',
           'X-Kin-Timestamp' => ts,
           'X-Kin-Signature' => "v1=#{signature}"
         }
  end

  let(:valid_payload) do
    {
      shopify_domain: 'merchant-42.myshopify.com',
      shopify_access_token: 'shpat_live_token_xyz',
      shopify_store_name: 'Merchant 42',
      scopes: 'read_orders,read_customers,read_shipping',
      account_id: account.id
    }
  end

  describe 'POST /api/kin/v1/installations' do
    context 'with a valid signature' do
      it 'creates the installation' do
        expect { signed_post(valid_payload) }.to change(Kin::ShopifyInstallation, :count).by(1)

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body['shopify_domain']).to eq('merchant-42.myshopify.com')
        expect(body['account_id']).to eq(account.id)

        installation = Kin::ShopifyInstallation.find(body['id'])
        expect(installation.shopify_access_token).to eq('shpat_live_token_xyz')
        expect(installation.scopes).to eq('read_orders,read_customers,read_shipping')
      end

      it 'upserts on duplicate shopify_domain' do
        existing = create(
          :kin_shopify_installation,
          account: account,
          shopify_domain: valid_payload[:shopify_domain],
          shopify_access_token: 'shpat_old_token'
        )

        expect { signed_post(valid_payload) }.not_to change(Kin::ShopifyInstallation, :count)

        existing.reload
        expect(existing.shopify_access_token).to eq('shpat_live_token_xyz')
        expect(existing.scopes).to eq('read_orders,read_customers,read_shipping')
        expect(existing.uninstalled_at).to be_nil
      end

      it 'returns 404 when the account does not exist' do
        signed_post(valid_payload.merge(account_id: 0))

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body['error']).to eq('account_not_found')
      end

      it 'returns 422 when required params are missing' do
        signed_post(valid_payload.merge(shopify_domain: ''))

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['errors']).to be_an(Array).and be_present
      end
    end

    context 'with no signature headers' do
      it 'returns 401' do
        post '/api/kin/v1/installations',
             params: valid_payload.to_json,
             headers: { 'CONTENT_TYPE' => 'application/json' }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with a bad signature' do
      it 'returns 401' do
        signed_post(valid_payload, secret: 'wrong-secret')

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with a stale timestamp' do
      it 'returns 401' do
        signed_post(valid_payload, skew: -10 * 60)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with a replayed signature' do
      it 'returns 401 on the second identical request' do
        call_count = 0
        allow(::Redis::Alfred).to receive(:set) do
          call_count += 1
          call_count == 1
        end

        signed_post(valid_payload)
        expect(response).to have_http_status(:created)

        signed_post(valid_payload)
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the shared secret is not configured' do
      it 'returns 401' do
        allow(ENV).to receive(:fetch).with('KIN_INSTALLATION_SHARED_SECRET', nil).and_return(nil)

        signed_post(valid_payload)

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
