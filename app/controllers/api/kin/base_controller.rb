# frozen_string_literal: true

# Layer 3 — Base controller for server-to-server Kin endpoints.
#
# Auth: HMAC-SHA256 over `${X-Kin-Timestamp}.${raw_body}` using
# ENV['KIN_INSTALLATION_SHARED_SECRET'] (see `Kin::InstallationSignatureVerifier`).
# We do NOT inherit from `PlatformController`: the Shopify-app process
# must not hold a Chatwoot PlatformApp token, so the shared secret is
# distinct and scoped only to this internal mirror surface.
#
# Subclasses get `verify_kin_installation_signature!` as a `before_action`.
# Controllers called from the browser (Shopify session-token path, Phase 1.1)
# should NOT inherit from this; they need their own base with session-token
# verification.
module Api
  module Kin
    class BaseController < ActionController::API
      include RequestExceptionHandler

      before_action :verify_kin_installation_signature!

      private

      def verify_kin_installation_signature!
        result = ::Kin::InstallationSignatureVerifier.verify(
          raw_body: request.raw_post,
          timestamp_header: request.headers['X-Kin-Timestamp'],
          signature_header: request.headers['X-Kin-Signature']
        )

        return if result.ok?

        Rails.logger.info("[kin:api] rejected request: #{result.error}")
        render json: { error: 'unauthorized' }, status: :unauthorized
      end
    end
  end
end
