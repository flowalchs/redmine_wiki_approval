# frozen_string_literal: true

require_dependency 'wiki_controller'

module RedmineWikiApproval
  module Patches
    module WikiControllerPatch
      extend ActiveSupport::Concern

      included do
        prepend InstanceOverwriteMethods

        after_action :wiki_approval_save, only: [:update]
        append_before_action :set_wiki_approval_data, only: [:show, :edit, :update]
        append_before_action :mark_edit_context, only: [:edit]
        append_before_action :apply_content_draft_update, only: [:update]
      end

      module InstanceOverwriteMethods
        def set_wiki_approval_data
          return unless @project && RedmineWikiApproval.is_enabled?(@project)

          # draft, approval or contentDraft must be enabled in project or plugin
          setting = WikiApprovalSetting.find_or_create(@project.id)
          return unless RedmineWikiApproval.approval_or_draft_enabled?(@project, setting) || RedmineWikiApproval.content_draft?(@project, setting)

          # @page nil from :update controller comment_required
          if @page.nil? && @wiki.present?
            page_identifier = params[:id] || params[:title]
            @page = @wiki.find_page(page_identifier) if page_identifier.present?
          end

          # @page or param
          view_version = params[:version] || @page&.version

          # @page must be there
          approval = @page ? WikiApprovalWorkflow.for_wiki(@page.id, view_version.to_i).first : nil
          latest_public = @page ? WikiApprovalWorkflow.latest_public_version_nr(@page) : nil

          @wiki_approval_data = {
            view_version_id: view_version&.to_i,
            approval: approval,
            latest_public_version: latest_public,
            setting: setting,
            step_approval: WikiApprovalWorkflowSteps.first_pending_step_for(approval, User.current, @project, params[:step_id])
          }
        end

        def wiki_approval_save
          return if @page.nil? || @page.errors.any?
          return unless @page.persisted?
          return if params[:draft].present?

          # check params
          status = params[:status]
          return true unless status

          status_disabled = params[:status_disabled]
          return true unless status_disabled

          return unless User.current.allowed_to?(:wiki_draft_create, @project)

          version = params[:version].present? ? params[:version].to_i : @page.version

          approval = WikiApprovalWorkflow.find_or_initialize_by(
            page_id: @page.id,
            version: version
          )

          approval.status = params[:status]
          approval.author_id ||= User.current.id
          approval.save!
        end

        def mark_edit_context
          return unless @project && RedmineWikiApproval.content_draft?(@project, nil)

          # parameter version is set, at rollback to prev version
          Thread.current[:wiki_edit_context] = params[:version].blank?
        end

        def apply_content_draft_update
          return unless @project && RedmineWikiApproval.content_draft?(@project, nil)

          @page = @wiki.find_or_new_page(params[:id])
          return unless @page.id # content drafts not on a new page

          # Thread parameter, is available later in the page model patch
          Thread.current[:wiki_is_draft] = params[:draft].present?
          Thread.current[:wiki_attachments] = params[:attachments] || (params[:wiki_page] && params[:wiki_page][:uploads])

          # not the best place, but before rendering, couldn't find a better spot
          flash.now[:notice] = l(:notice_successful_update) if Thread.current[:wiki_is_draft].present?

          # return unless section parameter
          return if params[:section].blank?

          draft = WikiApprovalDraft.find_by(page_id: @page.id)
          return unless draft

          base_text = draft.text

          # do section
          base_text = Redmine::WikiFormatting.formatter
            .new(base_text)
            .update_section(params[:section].to_i, params[:content][:text], params[:section_hash])

          # result in params vor normal update controller
          params[:content][:text] = base_text

          # Section-Parameter delete, all sections are append
          params.delete(:section)
          params.delete(:section_hash)
        end
      end
    end
  end
end
