# frozen_string_literal: true

class WikiApprovalSettingsController < ApplicationController
  layout 'base'

  before_action :find_project, :authorize, :find_user

  def update
    setting = WikiApprovalSetting.find_or_create @project.id
    begin
      setting.transaction do
        setting.update!(
          wiki_comment_required: params[:wiki_comment_required],
          wiki_draft_enabled: params[:wiki_draft_enabled],
          wiki_approval_enabled: params[:wiki_approval_enabled],
          wiki_approval_required: params[:wiki_approval_required],
          wiki_approval_version: params[:wiki_approval_version],
          wiki_content_draft: params[:wiki_content_draft],
          wiki_sidebar_status: params[:wiki_sidebar_status],
          wiki_templates: params[:wiki_templates]
        )
      end
      flash[:notice] = l(:notice_successful_update)
    rescue => e
      flash[:error] = "Updating failed." + e.message
    end

    redirect_to :controller => 'projects', :action => "settings", :id => @project, :tab => 'wiki_approval'
  end

  private

  def find_project
    # @project variable must be set before calling the authorize filter
    @project = Project.find(params[:project_id])
  end

  def find_user
    @user = User.current
  end
end
