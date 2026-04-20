# frozen_string_literal: true

# Layer 3 — Kin contact-notes CRUD. HMAC-authenticated via
# `Api::Kin::BaseController`. Notes are pinned to the Chatwoot Contact
# (not the Conversation) so they persist across tickets from the same
# customer; surfaced in the Notes tab of the Order Context sidebar.
#
# All actions take POST bodies. See the parent controller for the HMAC
# contract; replay protection runs off the body signature.
module Api
  module Kin
    module V1
      class ContactNotesController < BaseController
        def list
          return render(json: { error: 'account_not_found' }, status: :not_found) if account.nil?
          return render(json: { error: 'contact_not_found' }, status: :not_found) if contact.nil?

          notes = ::Kin::ContactNote
                  .where(account_id: account.id, contact_id: contact.id)
                  .includes(:author)
                  .ordered

          render json: { data: notes.map { |n| serialize(n) } }
        end

        def create
          return render(json: { error: 'account_not_found' }, status: :not_found) if account.nil?
          return render(json: { error: 'contact_not_found' }, status: :not_found) if contact.nil?
          return render(json: { error: 'author_not_found' }, status: :not_found) if author.nil?

          note = ::Kin::ContactNote.new(
            account_id: account.id,
            contact_id: contact.id,
            author_id: author.id,
            body: mutation_params[:body],
            pinned_at: cast_bool(mutation_params[:pinned]) ? Time.current : nil
          )

          if note.save
            render json: serialize(note), status: :created
          else
            render json: { errors: note.errors.full_messages }, status: :unprocessable_entity
          end
        end

        def update
          note = scoped_note
          return head :not_found if note.nil?

          attrs = {}
          attrs[:body] = mutation_params[:body] if mutation_params.key?(:body)
          if mutation_params.key?(:pinned)
            attrs[:pinned_at] = cast_bool(mutation_params[:pinned]) ? (note.pinned_at || Time.current) : nil
          end

          if note.update(attrs)
            render json: serialize(note)
          else
            render json: { errors: note.errors.full_messages }, status: :unprocessable_entity
          end
        end

        def destroy
          scoped_note&.destroy
          head :no_content
        end

        private

        def scoped_note
          ::Kin::ContactNote.find_by(id: params[:id], account_id: account&.id)
        end

        def mutation_params
          @mutation_params ||= params.permit(
            :id,
            :account_id,
            :contact_id,
            :author_id,
            :body,
            :pinned
          )
        end

        def account
          @account ||= Account.find_by(id: mutation_params[:account_id])
        end

        def contact
          @contact ||= account&.contacts&.find_by(id: mutation_params[:contact_id])
        end

        def author
          @author ||= account&.users&.find_by(id: mutation_params[:author_id])
        end

        def cast_bool(value)
          ActiveModel::Type::Boolean.new.cast(value)
        end

        def serialize(note)
          {
            id: note.id,
            account_id: note.account_id,
            contact_id: note.contact_id,
            body: note.body,
            pinned_at: note.pinned_at,
            author: { id: note.author_id, name: note.author&.name },
            created_at: note.created_at,
            updated_at: note.updated_at
          }
        end
      end
    end
  end
end
