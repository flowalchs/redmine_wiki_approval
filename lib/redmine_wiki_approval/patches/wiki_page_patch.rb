# frozen_string_literal: true

module RedmineWikiApproval
  module Patches
    module WikiPagePatch
      extend ActiveSupport::Concern

      included do
        prepend InstanceOverwriteMethods

        has_many :wiki_approval_workflows,
                class_name: 'WikiApprovalWorkflow',
                foreign_key: :page_id,
                dependent: :destroy
        has_one :current_wiki_aw,
                 class_name: 'WikiApprovalWorkflow',
                 foreign_key: :current_page_id
        has_many :wiki_approval_draft,
                class_name: 'WikiApprovalDraft',
                foreign_key: :page_id,
                dependent: :destroy
        after_save :delete_draft_after_publish
        attr_accessor :use_draft_content
      end

      module InstanceOverwriteMethods
        # overwrite from wiki controller update
        def save_with_content(content)
          # start workflow as draft, with new content version
          if Thread.current[:workflow_is_draft]
            result = false

            transaction do
              result = super # Versuche das originale Speichern

              if result
                result = WikiApprovalWorkflow.save_for_draft(
                  page: content.page,
                  content: content,
                  user: User.current,
                  status: Thread.current[:workflow_is_draft],
                  wiki_approval_data: Thread.current[:wiki_approval_data]
                )
              end
              # Das Rollback macht 'super' rückgängig
              raise ActiveRecord::Rollback if content.errors.any?
            end
            return result && !content.errors.any?
          end

          super
        ensure
          Thread.current[:workflow_is_draft] = nil
          Thread.current[:wiki_approval_data] = nil
        end

        def content_for_version(version=nil)
          # overwrite from wiki controller show edit
          if use_draft_content
            draft = WikiApprovalDraft.find_by(page_id: id)
            # get draft if available, return it as a content
            if draft
              content = WikiContent.new(page: self)
              content.text = draft.text
              content.comments = nil
              content.version = nil
              return content
            end
          end

          super
        end

        def delete_draft_after_publish
          WikiApprovalDraft.where(page_id: id).delete_all
        end
      end
    end
  end
end
