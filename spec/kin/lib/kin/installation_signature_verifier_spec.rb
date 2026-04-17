# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Kin::InstallationSignatureVerifier do
  let(:secret) { 'unit-test-secret' }
  let(:body) { '{"shopify_domain":"x.myshopify.com"}' }
  let(:now) { Time.zone.at(1_800_000_000) }
  let(:timestamp) { now.to_i.to_s }

  before { allow(::Redis::Alfred).to receive(:set).and_return(true) }

  def sign(ts, payload, sig_secret: secret)
    'v1=' + OpenSSL::HMAC.hexdigest('SHA256', sig_secret, "#{ts}.#{payload}")
  end

  def call(**overrides)
    described_class.verify(
      raw_body: body,
      timestamp_header: timestamp,
      signature_header: sign(timestamp, body),
      secret: secret,
      now: now,
      **overrides
    )
  end

  it 'accepts a well-formed signature' do
    expect(call).to be_ok
  end

  it 'rejects when the shared secret is blank' do
    result = call(secret: '')
    expect(result).not_to be_ok
    expect(result.error).to eq('shared_secret_not_configured')
  end

  it 'rejects when headers are missing' do
    expect(call(timestamp_header: '').error).to eq('missing_signature_headers')
    expect(call(signature_header: '').error).to eq('missing_signature_headers')
  end

  it 'rejects a non-v1 signature prefix' do
    result = call(signature_header: 'v2=deadbeef')
    expect(result.error).to eq('malformed_signature')
  end

  it 'rejects a non-numeric timestamp' do
    result = call(timestamp_header: 'not-a-number')
    expect(result.error).to eq('invalid_timestamp')
  end

  it 'rejects timestamps outside the ±5min window' do
    stale = (now.to_i - (6 * 60)).to_s
    result = call(timestamp_header: stale, signature_header: sign(stale, body))
    expect(result.error).to eq('timestamp_out_of_window')
  end

  it 'rejects a signature that does not match the body' do
    result = call(signature_header: sign(timestamp, 'tampered-body'))
    expect(result.error).to eq('signature_mismatch')
  end

  it 'rejects replayed signatures when Redis reports the nonce exists' do
    allow(::Redis::Alfred).to receive(:set).and_return(false)
    expect(call.error).to eq('replayed_signature')
  end

  it 'fails closed when Redis raises' do
    allow(::Redis::Alfred).to receive(:set).and_raise(StandardError.new('redis down'))
    expect(call.error).to eq('replayed_signature')
  end
end
