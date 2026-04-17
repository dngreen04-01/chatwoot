# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::Kin::V1::InstallationsController, type: :request do
  let(:account) { create(:account) }
  let(:platform_app) { create(:platform_app) }
  let(:access_token) { platform_app.access_token.token }

  before do
    platform_app.platform_app_permissibles.find_or_create_by!(permissible: account)
  end

  describe 'POST /api/kin/v1/installations' do
    let(:params) do
      {
        shopify_domain: 'merchant-42.myshopify.com',
        shopify_access_token: 'shpat_live_token_xyz',
        shopify_store_name: 'Merchant 42',
        scopes: 'read_orders,read_customers,read_shipping',
        account_id: account.id
      }
    end

    context 'without a platform token' do
      it 'returns 401' do
        post '/api/kin/v1/installations', params: params
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with a valid platform token' do
      let(:headers) { { api_access_token: access_token } }

      it 'creates an installation and encrypts the token' do
        expect {
          post '/api/kin/v1/installations', params: params, headers: headers
        }.to change(Kin::ShopifyInstallation, :count).by(1)

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body['shopify_domain']).to eq('merchant-42.myshopify.com')

        installation = Kin::ShopifyInstallation.find(body['id'])
        expect(installation.shopify_access_token).to eq('shpat_live_token_xyz')

        if Chatwoot.encryption_configured?
          raw = installation.read_attribute_before_type_cast(:shopify_access_token).to_s
          expect(raw).not_to include('shpat_live_token_xyz')
        end
      end

      it 'upserts on duplicate shopify_domain' do
        existing = create(
          :kin_shopify_installation,
          account: account,
          shopify_domain: params[:shopify_domain],
          shopify_access_token: 'shpat_old_token'
        )

        expect {
          post '/api/kin/v1/installations', params: params, headers: headers
        }.not_to change(Kin::ShopifyInstallation, :count)

        existing.reload
        expect(existing.shopify_access_token).to eq('shpat_live_token_xyz')
        expect(existing.scopes).to eq('read_orders,read_customers,read_shipping')
      end
    end
  end
end
