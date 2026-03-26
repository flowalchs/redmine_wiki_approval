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
        has_many :wiki_approval_draft,
                class_name: 'WikiApprovalDraft',
                foreign_key: :page_id,
                dependent: :destroy
        after_save :delete_draft_after_publish
      end

      module InstanceOverwriteMethods
        def save_with_content(content)
          # overwrite from wiki controller update
          # save as draft
          if Thread.current[:wiki_is_draft]

            latest_content = content.versions.find_by_version(content.version)
            draft = WikiApprovalDraft.find_or_initialize_by(page_id: content.page.id)

            # if text is same then last version, delete draft
            if latest_content && latest_content.text == content.text && draft.persisted?
              draft.destroy
              return false
            end

            # update conten Draft
            draft.update!(
              author_id: User.current.id,
              text: content.text)

            # attachments save
            Attachment.attach_files(content.page, Thread.current[:wiki_attachments]) if Thread.current[:wiki_attachments].present?

            return false
          end

          super
        ensure
          Thread.current[:wiki_is_draft] = nil
          Thread.current[:wiki_attachments] = nil
        end

        def content_for_version(version=nil)
          # overwrite from wiki controller show edit
          if Thread.current[:wiki_edit_context]
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
        ensure
          Thread.current[:wiki_edit_context] = nil
        end

        def delete_draft_after_publish
          WikiApprovalDraft.where(page_id: id).delete_all
        end
      end
    end
  end
end
