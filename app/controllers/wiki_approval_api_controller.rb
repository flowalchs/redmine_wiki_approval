# frozen_string_literal: true

class WikiApprovalApiController < ApplicationController
  accept_api_auth :update, :release, :submit, :approvers, :pending, :status, :statuses, :my_tasks

  before_action :find_project, :find_user
  before_action :check_module_enabled, :authorize
  before_action :find_wiki_page, only: [:release, :submit, :status]
  before_action :find_or_create_wiki_page, only: [:update]

  MAX_APPROVERS_PER_STEP = 50

  # PUT /projects/:project_id/wiki_approval_api/:title.json
  # Save draft (auto-creates page)
  def update
    content = @page.content || @page.build_content
    wp = wiki_page_params
    content.text = wp[:text] if wp.key?(:text)
    content.comments = wp[:comments] if wp.key?(:comments)
    content.author = User.current

    result = nil
    ActiveRecord::Base.transaction do
      unless content.save
        result = { error: true, target: content }
        raise ActiveRecord::Rollback
      end

      workflow = WikiApprovalWorkflow.find_or_initialize_by(
        page_id: @page.id,
        version: content.version
      )
      workflow.status = :draft
      workflow.author_id ||= User.current.id
      workflow.save!

      result = {
        error: false,
        data: { status: 'draft', wiki_page: @page.title,
                version: content.version, workflow_id: workflow.id }
      }
    end

    if result[:error]
      respond_to { |f| f.api { render_validation_errors(result[:target]) } }
    else
      respond_to { |f| f.api { render json: result[:data], status: :ok } }
    end
  end

  # POST /projects/:project_id/wiki_approval_api/:title/release.json
  # Release a draft directly (skip approval) — admin or approval_grant permission only
  def release
    workflow = find_current_draft_workflow
    return render_not_found_workflow unless workflow

    workflow.update!(status: :released)

    respond_to do |format|
      format.api do
        render json: {
          status: 'released',
          wiki_page: @page.title,
          version: workflow.version
        }, status: :ok
      end
    end
  end

  # POST /projects/:project_id/wiki_approval_api/:title/submit.json
  # Submit a draft for approval
  def submit
    workflow = find_current_draft_workflow
    return render_not_found_workflow unless workflow

    step_entries = normalize_step_entries
    return unless step_entries

    created_steps = 0
    submit_failed = false

    ActiveRecord::Base.transaction do
      step_entries.each do |entry|
        step_nr = entry[:step].to_i
        step_type = (entry[:step_type] || 'or').to_sym

        Array(entry[:principal_ids]).take(MAX_APPROVERS_PER_STEP).each do |pid|
          next if pid.to_i == User.current.id

          principal = User.find_by(id: pid) || Group.find_by(id: pid)
          next unless principal

          step = workflow.approval_steps.find_or_initialize_by(
            step: step_nr,
            principal_id: principal.id,
            principal_type: principal.class.name
          )
          step.step_status = :unstarted
          step.step_type = step_type
          step.save!
          created_steps += 1
        end
      end

      if created_steps == 0
        submit_failed = true
        raise ActiveRecord::Rollback
      end

      workflow.approval_steps.where(step: 1, step_status: :unstarted).find_each do |s|
        s.update!(step_status: :pending)
      end

      workflow.update!(status: :pending, author_id: User.current.id)
    end

    if submit_failed
      respond_to do |format|
        format.api { render json: { error: 'No valid approvers found' }, status: :unprocessable_entity }
      end
      return
    end

    begin
      WikiApprovalMailer.deliver_wiki_approval_step(workflow, @page, User.current, 1)
    rescue StandardError => e
      Rails.logger.warn("Wiki approval email failed: #{e.message}")
    end

    respond_to do |format|
      format.api do
        render json: {
          status: 'pending',
          wiki_page: @page.title,
          version: workflow.version,
          steps: workflow.approval_steps.order(:step, :id).map do |s|
            { step: s.step, step_type: s.step_type, principal_id: s.principal_id,
              principal_type: s.principal_type, status: s.status }
          end
        }, status: :ok
      end
    end
  end

  # GET /projects/:project_id/wiki_approval_api/approvers.json
  # List users/groups with wiki_approval_grant permission
  # Self-approval is prevented at submit time (submit action skips current user)
  def approvers
    users = []
    groups = []

    @project.memberships.includes(:principal, :roles).each do |m|
      if (u = m.user)
        next if u.admin?

        has_permission = m.roles.any? { |r| Array(r.permissions).include?(:wiki_approval_grant) }
        users << { id: u.id, name: u.name, type: 'User' } if has_permission
      end
      if (p = m.principal).is_a?(Group)
        has_permission = p.memberships.where(project_id: @project.id).any? do |gm|
          gm.roles.any? { |r| Array(r.permissions).include?(:wiki_approval_grant) }
        end
        groups << { id: p.id, name: p.name, type: 'Group' } if has_permission
      end
    end

    respond_to do |format|
      format.api { render json: { approvers: users + groups }, status: :ok }
    end
  end

  # GET /projects/:project_id/wiki_approval_api/pending.json
  # List pages with pending approval
  def pending
    wiki = @project.wiki
    return render_404 unless wiki

    workflows = WikiApprovalWorkflow.joins(:wiki_page)
                  .where(wiki_pages: { wiki_id: wiki.id })
                  .where(status: :pending)
                  .includes(:wiki_page, :approval_steps)
                  .limit(50)

    respond_to do |format|
      format.api do
        render json: {
          pending: workflows.map do |w|
            {
              wiki_page: w.wiki_page.title,
              version: w.version,
              author_id: w.author_id,
              created_at: w.created_at,
              steps: w.approval_steps.map do |s|
                { principal_id: s.principal_id, principal_type: s.principal_type, status: s.status }
              end
            }
          end
        }, status: :ok
      end
    end
  end

  # GET /projects/:project_id/wiki_approval_api/statuses.json
  # Bulk: latest workflow status for every wiki page
  def statuses
    wiki = @project.wiki
    return render_404 unless wiki

    pages = wiki.pages.includes(:content)

    latest_ids = WikiApprovalWorkflow
                   .where(page_id: pages.select(:id))
                   .group(:page_id)
                   .maximum(:id)

    latest_workflows = WikiApprovalWorkflow
                         .where(id: latest_ids.values)
                         .index_by(&:page_id)

    result = pages.map do |page|
      wf = latest_workflows[page.id]
      {
        title: page.title,
        version: page.content&.version,
        status: wf ? wf.status : 'released'
      }
    end

    respond_to do |format|
      format.api { render json: { statuses: result }, status: :ok }
    end
  end

  # GET /projects/:project_id/wiki_approval_api/:title/status.json
  # Workflow status for a single page
  def status
    workflows = WikiApprovalWorkflow.where(page_id: @page.id)
                  .order(version: :desc)
                  .limit(5)
                  .includes(:approval_steps)

    respond_to do |format|
      format.api do
        render json: {
          wiki_page: @page.title,
          workflows: workflows.map do |w|
            {
              version: w.version,
              status: w.status,
              author_id: w.author_id,
              created_at: w.created_at,
              updated_at: w.updated_at,
              steps: w.approval_steps.map do |s|
                {
                  step: s.step,
                  principal_id: s.principal_id,
                  principal_type: s.principal_type,
                  status: s.status,
                  note: s.note
                }
              end
            }
          end
        }, status: :ok
      end
    end
  end

  # GET /projects/:project_id/wiki_approval_api/my_tasks.json
  # Pending approval tasks assigned to current user
  def my_tasks
    wiki = @project.wiki
    return render_404 unless wiki

    group_ids = User.current.groups.pluck(:id)

    base = WikiApprovalWorkflowSteps
             .joins(approval: :wiki_page)
             .where(wiki_pages: { wiki_id: wiki.id })
             .where(status: :pending)

    steps = if group_ids.any?
              t = WikiApprovalWorkflowSteps.arel_table
              base.where(
                t[:principal_id].eq(User.current.id).and(t[:principal_type].eq('User'))
                  .or(t[:principal_id].in(group_ids).and(t[:principal_type].eq('Group')))
              ).includes(approval: :wiki_page).limit(50)
            else
              base.where(principal_id: User.current.id, principal_type: 'User')
                  .includes(approval: :wiki_page).limit(50)
            end

    respond_to do |format|
      format.api do
        render json: {
          tasks: steps.map do |s|
            {
              wiki_page: s.approval.wiki_page.title,
              version: s.approval.version,
              step: s.step,
              step_id: s.id,
              workflow_status: s.approval.status
            }
          end
        }, status: :ok
      end
    end
  end

  private

  def find_project
    @project = Project.find(params[:project_id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_user
    @user = User.current
  end

  def check_module_enabled
    render_403 unless RedmineWikiApproval.is_enabled?(@project)
  end

  def find_wiki_page
    wiki = @project.wiki
    return render_404 unless wiki

    @page = wiki.find_page(params[:title])
    render_404 unless @page
  end

  def find_or_create_wiki_page
    wiki = @project.wiki
    return render_404 unless wiki

    @page = wiki.find_page(params[:title])
    return if @page

    @page = WikiPage.new(wiki: wiki, title: Wiki.titleize(params[:title]))
    unless @page.save
      respond_to { |f| f.api { render_validation_errors(@page) } }
      return
    end
  end

  def find_current_draft_workflow
    WikiApprovalWorkflow.where(page_id: @page.id, status: :draft)
                        .order(version: :desc)
                        .first
  end

  def render_not_found_workflow
    respond_to do |format|
      format.api { render json: { error: 'No draft workflow found for this page' }, status: :not_found }
    end
  end

  def wiki_page_params
    params.require(:wiki_page).permit(:text, :comments)
  end

  def normalize_step_entries
    steps_param = params[:steps]
    legacy_approvers = params[:approvers]

    if steps_param.blank? && legacy_approvers.blank?
      respond_to do |format|
        format.api { render json: { error: 'steps or approvers parameter is required' }, status: :unprocessable_entity }
      end
      return nil
    end

    if steps_param.present?
      Array(steps_param).map { |s| s.permit(:step, :step_type, principal_ids: []).to_h.symbolize_keys }
    else
      [{ step: 1, step_type: 'or', principal_ids: Array(legacy_approvers) }]
    end
  end
end
