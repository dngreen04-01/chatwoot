# frozen_string_literal: true

# Wires Kin::ContactAccessLogDecorator onto Chatwoot's core
# ContactsController and ConversationsController at boot. Layer-3
# Chatwoot fork discipline: no edits to the controller files
# themselves — the decorator is prepended here.
#
# `to_prepare` is the Rails 7 idiom for controller prepending: it
# runs on boot and on every dev-mode code reload, so reloading a
# controller doesn't strip the prepend. Prepend is idempotent, so
# firing it more than once is safe.
Rails.application.config.to_prepare do
  Api::V1::Accounts::ContactsController.prepend(Kin::ContactAccessLogDecorator)
  Api::V1::Accounts::ConversationsController.prepend(Kin::ContactAccessLogDecorator)
end
