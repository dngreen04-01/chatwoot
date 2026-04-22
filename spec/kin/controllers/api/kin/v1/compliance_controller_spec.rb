# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::Kin::V1::ComplianceController, type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:shop_domain) { 'kin-compliance-spec.myshopify.com' }
  let(:other_shop_domain) { 'kin-compliance-other.myshopify.com' }
  let(:shared_secret) { 'kin-test-shared-secret' }

  let!(:installation) do
    create(:kin_shopify_installation, account: account, shopify_domain: shop_domain)
  end

  let!(:other_installation) do
    create(:kin_shopify_installation, account: other_account, shopify_domain: other_shop_domain)
  end

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('KIN_INSTALLATION_SHARED_SECRET', nil).and_return(shared_secret)
    allow(::Redis::Alfred).to receive(:set).and_return(true)
  end

  def signed_post(path, body_hash, secret: shared_secret, tamper: false)
    body = body_hash.to_json
    ts = Time.current.to_i.to_s
    signature = OpenSSL::HMAC.hexdigest('SHA256', secret, "#{ts}.#{body}")
    send_body = tamper ? body_hash.merge(_tampered: true).to_json : body

    post path,
         params: send_body,
         headers: {
           'CONTENT_TYPE' => 'application/json',
           'X-Kin-Timestamp' => ts,
           'X-Kin-Signature' => "v1=#{signature}"
         }
  end

  describe 'POST /api/kin/v1/compliance/customer_redact' do
    let(:contact) do
      create(:contact,
             account: account,
             name: 'Lena Merchant',
             email: 'lena@example.com',
             phone_number: '+64211111111')
    end

    let(:payload) do
      { shop_domain: shop_domain, customer: { id: 99, email: contact.email, phone: contact.phone_number } }
    end

    it 'scrubs matching contact PII' do
      note = create(:kin_contact_note, account: account, contact: contact)

      signed_post('/api/kin/v1/compliance/customer_redact', payload)

      expect(response).to have_http_status(:ok)
      contact.reload
      expect(contact.name).to eq('[redacted]')
      expect(contact.email).to be_nil
      expect(contact.phone_number).to be_nil
      expect(contact.identifier).to be_nil
      expect(contact.additional_attributes).to eq({})
      expect(contact.custom_attributes).to eq({})
      expect(::Kin::ContactNote.where(id: note.id)).to be_empty
    end

    it 'does not touch contacts on other accounts' do
      foreign_contact = create(:contact,
                               account: other_account,
                               name: 'Lena Other',
                               email: contact.email)

      signed_post('/api/kin/v1/compliance/customer_redact', payload)

      foreign_contact.reload
      expect(foreign_contact.name).to eq('Lena Other')
      expect(foreign_contact.email).to eq(contact.email)
    end

    it 'acks 200 when the email does not match any contact' do
      signed_post('/api/kin/v1/compliance/customer_redact',
                  payload.merge(customer: { id: 99, email: 'ghost@example.com' }))

      expect(response).to have_http_status(:ok)
    end

    it 'returns 404 when the shop is not installed' do
      signed_post('/api/kin/v1/compliance/customer_redact',
                  payload.merge(shop_domain: 'never-seen.myshopify.com'))

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 422 when shop_domain is missing' do
      signed_post('/api/kin/v1/compliance/customer_redact', payload.except(:shop_domain))

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rejects unsigned requests with 401' do
      post '/api/kin/v1/compliance/customer_redact',
           params: payload.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects tampered bodies with 401' do
      signed_post('/api/kin/v1/compliance/customer_redact', payload, tamper: true)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/kin/v1/compliance/customer_data_request' do
    it 'acks 200 and logs the payload' do
      logged = []
      allow(Rails.logger).to receive(:info).and_wrap_original do |original, *args, &block|
        logged << args.first.to_s if args.first.is_a?(String)
        original.call(*args, &block)
      end

      signed_post('/api/kin/v1/compliance/customer_data_request',
                  { shop_domain: shop_domain, customer: { id: 99, email: 'x@example.com' } })

      expect(response).to have_http_status(:ok)
      expect(logged).to include(match(/customer_data_request received/))
    end

    it 'returns 422 when shop_domain is missing' do
      signed_post('/api/kin/v1/compliance/customer_data_request', { customer: { id: 99 } })

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rejects unsigned requests with 401' do
      post '/api/kin/v1/compliance/customer_data_request',
           params: { shop_domain: shop_domain }.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/kin/v1/compliance/shop_redact' do
    it 'enqueues the ShopRedactJob for the installed shop' do
      expect(::Kin::Compliance::ShopRedactJob).to receive(:set).with(wait: instance_of(ActiveSupport::Duration)).and_return(::Kin::Compliance::ShopRedactJob)
      expect(::Kin::Compliance::ShopRedactJob).to receive(:perform_later).with(shop_domain: shop_domain, account_id: account.id)

      signed_post('/api/kin/v1/compliance/shop_redact', { shop_domain: shop_domain })

      expect(response).to have_http_status(:ok)
    end

    it 'acks 200 without enqueuing when the shop is unknown' do
      expect(::Kin::Compliance::ShopRedactJob).not_to receive(:set)

      signed_post('/api/kin/v1/compliance/shop_redact', { shop_domain: 'never-seen.myshopify.com' })

      expect(response).to have_http_status(:ok)
    end

    it 'returns 422 when shop_domain is missing' do
      signed_post('/api/kin/v1/compliance/shop_redact', {})

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rejects unsigned requests with 401' do
      post '/api/kin/v1/compliance/shop_redact',
           params: { shop_domain: shop_domain }.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
