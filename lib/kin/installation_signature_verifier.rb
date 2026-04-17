# frozen_string_literal: true

# Layer 3 — HMAC verifier for server-to-server calls from the Shopify
# app (personal-kin/kin) into the Rails Kin API. Used by
# `Api::Kin::BaseController` to authenticate `POST /api/kin/v1/installations`
# and any future internal mirrors.
#
# Request shape (produced by kin/app/lib/provisioning.server.ts):
#   headers:
#     X-Kin-Timestamp: "<unix seconds>"
#     X-Kin-Signature: "v1=<hex(hmac_sha256(secret, timestamp + '.' + raw_body))>"
#   body: raw request bytes (do NOT re-serialize)
#
# Shared secret lives in ENV['KIN_INSTALLATION_SHARED_SECRET']. The same
# secret is set on the Shopify-app process; neither the Chatwoot
# PlatformApp token nor Rails credentials are reused, so a compromise of
# one doesn't grant the other.
#
# Replay defence: the signature hex itself is used as a one-shot nonce in
# Redis (SET NX EX = 2 × timestamp_window). Any re-posted payload within
# the window is rejected as a duplicate.
module Kin
  class InstallationSignatureVerifier
    TIMESTAMP_WINDOW_SECONDS = 5 * 60
    SIGNATURE_PREFIX = 'v1='
    NONCE_KEY_PREFIX = 'kin:installation:nonce:'
    NONCE_TTL_SECONDS = TIMESTAMP_WINDOW_SECONDS * 2

    Result = Struct.new(:ok, :error, keyword_init: true) do
      def ok? = ok
    end

    def self.verify(raw_body:, timestamp_header:, signature_header:, secret: ENV.fetch('KIN_INSTALLATION_SHARED_SECRET', nil), now: Time.current)
      new(
        raw_body: raw_body,
        timestamp_header: timestamp_header,
        signature_header: signature_header,
        secret: secret,
        now: now
      ).verify
    end

    def initialize(raw_body:, timestamp_header:, signature_header:, secret:, now:)
      @raw_body = raw_body.to_s
      @timestamp_header = timestamp_header.to_s
      @signature_header = signature_header.to_s
      @secret = secret.to_s
      @now = now
    end

    def verify
      return fail_with('shared_secret_not_configured') if @secret.empty?
      return fail_with('missing_signature_headers') if @timestamp_header.empty? || @signature_header.empty?
      return fail_with('malformed_signature') unless @signature_header.start_with?(SIGNATURE_PREFIX)

      timestamp = Integer(@timestamp_header, 10)
      skew = (@now.to_i - timestamp).abs
      return fail_with('timestamp_out_of_window') if skew > TIMESTAMP_WINDOW_SECONDS

      provided = @signature_header.sub(SIGNATURE_PREFIX, '')
      expected = OpenSSL::HMAC.hexdigest('SHA256', @secret, "#{@timestamp_header}.#{@raw_body}")
      return fail_with('signature_mismatch') unless ActiveSupport::SecurityUtils.secure_compare(expected, provided)

      return fail_with('replayed_signature') unless claim_nonce(provided)

      Result.new(ok: true, error: nil)
    rescue ArgumentError
      fail_with('invalid_timestamp')
    end

    private

    # Returns true when the nonce was fresh, false when already seen.
    # If Redis is unavailable we fail closed — better to 401 a real
    # request than to silently disable replay protection.
    def claim_nonce(signature_hex)
      ::Redis::Alfred.set("#{NONCE_KEY_PREFIX}#{signature_hex}", '1', nx: true, ex: NONCE_TTL_SECONDS) ? true : false
    rescue StandardError => e
      Rails.logger.warn("[kin:installation_verifier] redis unavailable: #{e.class}: #{e.message}")
      false
    end

    def fail_with(reason)
      Result.new(ok: false, error: reason)
    end
  end
end
