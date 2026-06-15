# frozen_string_literal: true

require_dependency 'wiki_controller'

module RedmineWikiApproval
  module Patches
    module WikiControllerPatch
      extend ActiveSupport::Concern

      included do
        prepend InstanceOverwriteMethods

        append_before_action :set_wiki_approval_data, only: [:preview, :new]
        append_before_action :handle_edit_flow, only: [:edit]
        append_before_action :handle_update_flow, only: [:update]
        append_before_action :handle_show_flow, only: [:show]

        helper :wiki_approval_icon
        helper :wiki_approval
      end

      module InstanceOverwriteMethods
        def set_wiki_approval_data
          return unless @project && RedmineWikiApproval::Settings.is_enabled?(@project)

          # draft, approval or contentDraft must be enabled in project or plugin
          setting = WikiApprovalSetting.find_or_create(@project.id)
          return unless RedmineWikiApproval::Settings.approval_or_draft_enabled?(@project, setting) || RedmineWikiApproval::Settings.content_draft?(@project, setting)

          # @page nil from :update controller comment_required
          page = @page
          if page.nil? && @wiki.present?
            page_identifier = params[:id] || params[:title]
            page = @wiki.find_page(page_identifier) if page_identifier.present?
          end

          latest_public = page ? WikiApprovalWorkflow.latest_public_version_nr(page) : nil

          # show: redirect to version, if not set & enabled
          if action_name == 'show' &&
            params[:version].blank? &&
            !from_wiki_edit_referer? &&
            RedmineWikiApproval::Settings.is_allowed_to_show_last_version?(@project, setting) &&
            latest_public.present? && latest_public != page&.version

            redirect_to({ controller: 'wiki', action: 'show', project_id: @project.identifier, id: page.title, version: latest_public })
            return
          end

          # @page or param
          view_version = params[:version] || page&.version
          # @page must be there
          approval = page ? WikiApprovalWorkflow.for_wiki(page.id, view_version.to_i).first : nil

          @wiki_approval_data = {
            view_version_id: view_version&.to_i,
            approval: approval,
            latest_public_version: latest_public,
            setting: setting,
            step_approval: WikiApprovalWorkflowStep.first_pending_step_for(approval, User.current)
          }
        end

        def mark_edit_context
          return unless @project && RedmineWikiApproval::Settings.content_draft?(@project, nil)

          # parameter version is set, at rollback to prev version
          Thread.current[:wiki_edit_context] = params[:version].blank?
        end

        def apply_content_draft_update
          return unless @project && RedmineWikiApproval::Settings.content_draft?(@project, nil)

          page = @wiki.find_page(params[:id])
          if page.nil? # content drafts not on a new page
            params.delete(:draft) # delete parameter for later apply_workflow_draft_update
            return
          end

          # Thread parameter, is available later in the page model patch
          Thread.current[:wiki_is_draft] = params[:draft].present?
          Thread.current[:wiki_attachments] = params[:attachments] || (params[:wiki_page] && params[:wiki_page][:uploads])

          # not the best place, but before rendering, couldn't find a better spot
          flash.now[:notice] = l(:notice_successful_update) if Thread.current[:wiki_is_draft].present?

          # return unless section parameter
          return if params[:section].blank?

          draft = WikiApprovalDraft.find_by(page_id: page.id)
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

        def apply_workflow_draft_update
          return unless @wiki_approval_data # project not anaibled
          return if params[:draft].present? # content draft
          return unless RedmineWikiApproval::Settings.approval_or_draft_enabled?(@project, @wiki_approval_data[:setting]) # no workflow/draft enabled

          # Fallback: Default to "draft" status if params[:status] is blank or missing (e.g., via API)
          Thread.current[:workflow_is_draft] = params[:status].presence || "draft"
          Thread.current[:wiki_approval_data] = @wiki_approval_data
        end

        def history
          super

          return unless @versions && @page && RedmineWikiApproval::Settings.is_enabled?(@project)

          version_numbers = @versions.map(&:version)
          approvals = WikiApprovalWorkflow
            .where(page_id: @page.id, version: version_numbers)
            .includes(:approval_steps)
            .index_by(&:version)
          @wiki_approval_versions = approvals
        end

        def handle_update_flow
          set_wiki_approval_data
          apply_content_draft_update
          apply_workflow_draft_update
        end

        def handle_edit_flow
          set_wiki_approval_data
          mark_edit_context
        end

        def handle_show_flow
          set_wiki_approval_data
          check_version_authorization
        end

        # only patch when post and parameter rwa_template_id
        def new
          begin
            if request.post? && params[:rwa_template_id].present?
              @page = WikiPage.new(:wiki => @wiki, :title => params[:title])
              unless User.current.allowed_to?(:edit_wiki_pages, @project)
                render_403
                return
              end
              @page.title = '' unless editable?
              @page.validate
              if @page.errors[:title].blank?
                # path with additional parameter
                path = project_wiki_page_path(@project, @page.title, :parent => params[:parent], :rwa_template_id => params[:rwa_template_id])

                respond_to do |format|
                  format.html { redirect_to path }
                  format.js   { render :js => "window.location = #{path.to_json}" }
                end
                return
              end
            end
          rescue => e
            Rails.logger.error("new fallback plugin rwa triggered: #{e.class} - #{e.message}")
          end
          # fallback or no template_id
          super
        end

        # only patch when parameter rwa_template_id available and wiki_templates enabled
        def initial_page_content(page)
          begin
            if params[:rwa_template_id].present? && @wiki_approval_data &&
              (workflow = WikiApprovalWorkflow.find_by(id: params[:rwa_template_id])&.latest_public_version)

              if RedmineWikiApproval::WikiTemplates.new(
                project: @project,
                user: User.current,
                setting: @wiki_approval_data[:setting]
              ).accessible_template?(page: workflow.wiki_page)

                text = workflow.wiki_version&.text
                return text if text.present?
              end
            end
          rescue => e
            Rails.logger.error("initial_page_content plugin rwa fallback triggered: #{e.class} - #{e.message}")
          end

          # fallback or no text found
          super
        end

        private

        def from_wiki_edit_referer?
          referer = request.referer
          referer.present? && referer.include?('/wiki/') && referer.include?('edit')
        end

        def check_version_authorization
          return unless @wiki_approval_data
          return if RedmineWikiApproval::Settings.view_draft?(@project, @wiki_approval_data[:setting]) != false

          version = params[:version]&.to_i || @page.version
          return unless version

          approval = if @wiki_approval_data[:view_version_id] == version
                       @wiki_approval_data[:approval]
                     else
                       WikiApprovalWorkflow.for_wiki(@page.id, version).first
                     end

          raise ::Unauthorized if approval&.status_before_type_cast&.< WikiApprovalWorkflow.statuses[:published]
        end
      end
    end
  end
end
