# frozen_string_literal: true

class WikiApprovalController < ApplicationController
  include RedmineWikiApproval::Patches::WikiControllerPatch::InstanceOverwriteMethods

  menu_item :wiki
  before_action :find_project, :find_user
  before_action :check_module_enabled, :authorize
  before_action :find_page
  before_action :set_wiki_approval_data

  def start_approval
    # just if no approval is in the db
    @wiki_approval_data[:approval] ||= WikiApprovalWorkflow.find_or_initialize_by(
      page_id: @page.id,
      version: @page.content.version,
      status: :pending,
      author_id: User.current.id
    )

    # get
    if request.get?
      return render_403 unless RedmineWikiApproval.approval_start?(@project, @wiki_approval_data[:setting])

      @steps_grouped = @wiki_approval_data[:approval].steps_grouped_with_default if @wiki_approval_data[:approval]
      @approval_user_options = approval_user_options(@project, @page.content.author_id)
      @note = @wiki_approval_data[:approval]&.note.presence || @page.content.comments
      render template: 'workflow/start_approval'
      return
    end

    # update
    approval = @wiki_approval_data[:approval]

    # status check
    if approval.released?
      flash[:error] = l(:wiki_approval_unable_start_status, :status => l("wiki_approval_workflow.status.#{approval.status}"))
      redirect_to project_wiki_page_path(@project.identifier, @page.title, :version => @page.content.version)
      return
    end

    # no empty users
    steps_params = params[:steps].transform_values { |users| users.reject { |u| u["principal_id"].blank? } }

    # Globale doublicat users
    if duplicate_users?(steps_params)
      flash.now[:error] = l(:wiki_approval_unable_start_user)
      restore_form_data
      render template: 'workflow/start_approval'
      return
    end

    latest_notifiable_step = nil

    ActiveRecord::Base.transaction do
      # if approval is not saved
      @wiki_approval_data[:approval].save! if @wiki_approval_data[:approval].new_record?

      # ist ist already pending, for later mail
      approval_was_already_pending = (approval.status == 'pending')

      # save Steps
      steps_params.each do |step_nr, users|
        # Collect all user_ids for this step group
        user_ids = users.map { |u| u[:principal_id].to_i }
        # Delete all steps for this step_nr that are not in the submitted user_ids
        approval.approval_steps.where(step: step_nr).where.not(principal_id: user_ids).destroy_all

        approval.update(note: params[:note], author_id: User.current.id)

        # create new users for this step
        users.each do |user_data|
          principal_object = User.find_by(id: user_data[:principal_id]) || Group.find_by(id: user_data[:principal_id])
          step_record = approval.approval_steps.for_principal(principal_object).find_or_initialize_by(step: step_nr)

          # Only set status to :unstarted if current status !approved
          step_record.step_status = :unstarted if step_record.step_status.nil? || !step_record.step_status_approved?
          step_record.step_type = params[:steps_typ][step_nr] || 'or'

          # save if it changed anything
          if step_record.changed?
            step_record.save!

            # if it was a new record or changed record, in pending, then send a mail for this step
            if latest_notifiable_step.nil? &&
               approval_was_already_pending &&
               (step_record.saved_changes.key?('id') || (step_record.saved_change_to_attribute?('step_status') && step_record.step_status == 'pending'))
              latest_notifiable_step = step_nr
            end
          end
        end
      end

      @wiki_approval_data[:approval].approval_steps.check_all_steps_approved(approval)
    end

    # Send email after the transaction if step_nr was saved for it, or if the user was changed or is new
    WikiApprovalMailer.deliver_wiki_approval_step(approval, approval.wiki_page, User.current, latest_notifiable_step) if latest_notifiable_step

    redirect_to project_wiki_page_path(@project.identifier, @page.title, :version => @page.content.version)
  end

  def grant_approval
    @step = @wiki_approval_data[:step_approval]

    # Check if all is available
    return render_404 unless @step

    if request.post?

      if params[:status] == 'rejected' && params[:note].blank?
        flash[:error] = l(:wiki_approval_unable_note)
        redirect_to project_wiki_page_path(@project.identifier, @page.title, :version => @page.content.version)
        return
      end

      @step.update({step_status: params[:status], note: params[:note], principal: User.current}.compact)
      redirect_to project_wiki_page_path(@project.identifier, @page.title, :version => @page.content.version)
    else
      respond_to do |format|
        format.js { render template: 'workflow/grant_approval', layout: false }
      end
    end
  end

  def forward_approval
    @step = @wiki_approval_data[:step_approval]

    # Check if all is available
    return render_404 unless @step

    if request.post?

      if params[:note].blank?
        flash[:error] = l(:wiki_approval_unable_note)
        redirect_to project_wiki_page_path(@project.identifier, @page.title, :version => @page.content.version)
        return
      end

      principal_object = User.find_by(id: params[:principal_id]) || Group.find_by(id: params[:principal_id])

      # doublicat users
      if WikiApprovalWorkflowSteps.for_principal(principal_object).where(wiki_approval_workflow_id: @step.approval.id).exists?
        flash[:error] = l(:wiki_approval_unable_start_user)
        redirect_to project_wiki_page_path(@project.identifier, @page.title, :version => @page.content.version)
        return
      end

      @step.update({note: params[:note], principal: principal_object}.compact)

      # notify users from the step
      WikiApprovalMailer.deliver_wiki_approval_step(@step.approval, @step.approval.wiki_page, User.current, @step.step)

      redirect_to project_wiki_page_path(@project.identifier, @page.title, :version => @page.content.version)
    else
      @approval_user_options = approval_user_options(@project, @page.content.author_id)
      respond_to do |format|
        format.js { render template: 'workflow/forward_approval', layout: false }
      end
    end
  end

  def view_draft
  end

  def set_draft
  end

  private

  def find_project
    # @project variable must be set before calling the authorize filter
    @project = Project.find(params[:project_id]) unless params[:project_id].blank?
  end

  def find_user
    @user = User.current
  end

  def find_page
    return render_404 unless params[:title] && params[:version]

    if params[:version] && params[:title]
      @page = WikiPage.joins(:wiki, :content)
                      .find_by(wikis: { project_id: @project.id }, title: params[:title], wiki_contents: { version: params[:version] })
    end

    return render_404 unless @page
  end

  def check_module_enabled
    render_403 unless RedmineWikiApproval.is_enabled? @project
  end

  def approval_user_options(project, autor_id)
    users  = []
    groups = []

    project.memberships.each do |m|
      # users
      if (u = m.user)
        next if u.admin? || u.id == autor_id

        users << u if u.allowed_to?(:wiki_approval_grant, project)
      end

      # groups
      if (p = m.principal).is_a?(Group)
        has_permission =
          p.memberships.where(project_id: project.id).any? do |gm|
            gm.roles.any? { |r| Array(r.permissions).include?(:wiki_approval_grant) }
          end
        groups << p if has_permission
      end
    end

    users + groups
  end

  def duplicate_users?(steps_params)
    # Converts Rails params into a hash or uses the hash if it already is one
    h = steps_params.respond_to?(:to_unsafe_h) ? steps_params.to_unsafe_h : steps_params
    return false unless h.respond_to?(:values)

    seen = Set.new
    h.values.each do |users|
      Array(users).each do |u|
        # Compact access to string or symbol keys
        user_id = (u["principal_id"] || u[:principal_id]).to_i
        next if user_id.zero?
        return true if seen.include?(user_id)

        seen.add(user_id)
      end
    end
    false
  end

  def restore_form_data
    @steps_grouped = build_steps_from_params
    @approval_user_options = approval_user_options(@project, @page.content.author_id)
  end

  def build_steps_from_params
    grouped = {}
    params[:steps].each do |step_nr, users|
      grouped[step_nr.to_i] = users.map do |u|
        principal_id = u["principal_id"]
        principal_object = User.find_by(id: principal_id) || Group.find_by(id: principal_id)

        WikiApprovalWorkflowSteps.new(
          step: step_nr,
          principal: principal_object,
          step_type: params[:steps_typ][step_nr]
        )
      end
    end
    grouped
  end
end
