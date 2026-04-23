# frozen_string_literal: true

# Layer 3 — Prepended onto Chatwoot's ContactsController and
# ConversationsController to record every successful `show` / `index`
# in kin_contact_access_logs. Wired in
# config/initializers/kin_contact_access_log.rb.
#
# Contract: this module must never raise into the request. If the log
# write fails, the error is logged and the original response is
# returned unchanged. An audit path that 500s the app is worse than
# one that silently fails.
module Kin
  module ContactAccessLogDecorator
    def self.prepended(base)
      base.around_action :kin_log_access, only: %i[show index]
    end

    private

    def kin_log_access
      yield

      begin
        kin_record_access!
      rescue StandardError => e
        Rails.logger.error(
          "[Kin::ContactAccessLog] logging failed: #{e.class}: #{e.message}"
        )
      end
    end

    def kin_record_access!
      return unless response&.successful?
      return unless Kin::ContactAccessLog::ACTIONS.include?(action_name)
      return if Current.account.nil? || Current.user.nil?

      Kin::ContactAccessLog.bulk_log([kin_access_log_row])
    end

    def kin_access_log_row
      now = Time.current
      {
        account_id: Current.account.id,
        agent_id: Current.user.id,
        contact_id: kin_resolve_contact_id,
        conversation_id: kin_resolve_conversation_id,
        action: action_name,
        accessed_at: now,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        created_at: now,
        updated_at: now
      }
    end

    def kin_resolve_contact_id
      return @contact.id if defined?(@contact) && @contact
      return @conversation.contact_id if defined?(@conversation) && @conversation

      nil
    end

    def kin_resolve_conversation_id
      return @conversation.id if defined?(@conversation) && @conversation

      nil
    end
  end
end
