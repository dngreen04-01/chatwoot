# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::Kin::V1::ContactNotesController, type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:contact) { create(:contact, :with_email, account: account) }
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

  describe 'POST /api/kin/v1/contact_notes/list' do
    it 'returns notes for the scoped contact in pin-then-recency order' do
      older = create(:kin_contact_note, account: account, contact: contact, created_at: 3.days.ago, body: 'older')
      newer = create(:kin_contact_note, account: account, contact: contact, created_at: 1.day.ago, body: 'newer')
      pinned = create(:kin_contact_note, account: account, contact: contact, pinned_at: 1.hour.ago, body: 'pinned')

      signed_request(:post, '/api/kin/v1/contact_notes/list',
                     { account_id: account.id, contact_id: contact.id })

      expect(response).to have_http_status(:ok)
      bodies = response.parsed_body['data'].map { |n| n['body'] }
      expect(bodies).to eq(%w[pinned newer older])
      expect([pinned, newer, older]).to all(be_a(Kin::ContactNote))
    end

    it 'isolates across accounts' do
      create(:kin_contact_note, account: account, contact: contact, body: 'private')
      signed_request(:post, '/api/kin/v1/contact_notes/list',
                     { account_id: other_account.id, contact_id: contact.id })

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq('contact_not_found')
    end
  end

  describe 'POST /api/kin/v1/contact_notes' do
    it 'creates a note scoped to the account + contact + author' do
      expect do
        signed_request(:post, '/api/kin/v1/contact_notes',
                       { account_id: account.id, contact_id: contact.id, author_id: agent.id, body: 'Refund sent.' })
      end.to change(Kin::ContactNote, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['body']).to eq('Refund sent.')
      expect(response.parsed_body['author']['id']).to eq(agent.id)
    end

    it 'rejects when body is empty' do
      signed_request(:post, '/api/kin/v1/contact_notes',
                     { account_id: account.id, contact_id: contact.id, author_id: agent.id, body: '' })

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rejects when the author is not in the account' do
      foreign_user = create(:user)

      signed_request(:post, '/api/kin/v1/contact_notes',
                     { account_id: account.id, contact_id: contact.id, author_id: foreign_user.id, body: 'x' })

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq('author_not_found')
    end

    it 'treats the string "false" as unpinned' do
      signed_request(:post, '/api/kin/v1/contact_notes',
                     { account_id: account.id, contact_id: contact.id, author_id: agent.id, body: 'x', pinned: 'false' })

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['pinned_at']).to be_nil
    end
  end

  describe 'PATCH /api/kin/v1/contact_notes/:id' do
    it 'updates the body and pin state' do
      note = create(:kin_contact_note, account: account, contact: contact, body: 'initial')

      signed_request(:patch, "/api/kin/v1/contact_notes/#{note.id}",
                     { account_id: account.id, body: 'updated', pinned: true })

      expect(response).to have_http_status(:ok)
      note.reload
      expect(note.body).to eq('updated')
      expect(note.pinned_at).not_to be_nil
    end

    it 'refuses to cross-account update' do
      note = create(:kin_contact_note, account: account, contact: contact)

      signed_request(:patch, "/api/kin/v1/contact_notes/#{note.id}",
                     { account_id: other_account.id, body: 'stolen' })

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/kin/v1/contact_notes/:id/destroy' do
    it 'deletes the note' do
      note = create(:kin_contact_note, account: account, contact: contact)

      signed_request(:post, "/api/kin/v1/contact_notes/#{note.id}/destroy",
                     { account_id: account.id })

      expect(response).to have_http_status(:no_content)
      expect(Kin::ContactNote.exists?(note.id)).to be(false)
    end
  end

  describe 'with no signature' do
    it 'returns 401' do
      post '/api/kin/v1/contact_notes/list',
           params: { account_id: account.id, contact_id: contact.id }.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
