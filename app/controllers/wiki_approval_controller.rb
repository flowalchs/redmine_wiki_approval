# frozen_string_literal: true

class WikiApprovalController < ApplicationController
  include RedmineWikiApproval::Patches::WikiControllerPatch::InstanceOverwriteMethods
  accept_api_auth :status, :start, :grant, :forward, :publish, :permissions, :index, :history

  menu_item :wiki
  before_action :find_project, :except => [:index]
  before_action :find_optional_project, :only => [:index]
  before_action :find_user
  before_action :check_module_enabled, :authorize, :except => [:index]
  before_action :find_page, :except => [:permissions, :index]
  before_action :set_wiki_approval_data, :except => [:permissions, :index]

  include QueriesHelper
  include SortHelper
  include RoutesHelper

  helper :queries
  helper :sort
  helper :routes

  def status
    return render_403 if request.format.html? && @content.version != @page.content.version

    # just if no approval is in the db
    @wiki_approval_data[:approval] ||= WikiApprovalWorkflow.find_or_initialize_by(
      page_id: @page.id,
      version: @content.version
    )

    # default values for html view
    if request.format.html?
      @approval_user_options = approval_user_options(@project, @content.author_id)
      @steps = @wiki_approval_data[:approval].approval_steps
      # 2. steps from last released-version
      if @steps.blank?
        @steps = WikiApprovalWorkflow
                    .where(page_id: @page.id, status: :released)
                    .order(version: :desc)
                    .first
                    &.approval_steps
      end
      # when step 1 is not there, default value
      @steps = [WikiApprovalWorkflowStep.new(step: 1, step_type: :or)] if @steps.blank?
      @note = @wiki_approval_data[:approval]&.note.presence || @content.comments
    end

    respond_to do |format|
      format.html do
        render template: 'wiki_approval/start'
      end
      format.api
    end
  end

  def start
    # just if no approval is in the db
    @wiki_approval_data[:approval] ||= WikiApprovalWorkflow.find_or_initialize_by(
      page_id: @page.id,
      version: @page.content.version
    )

    # update
    approval = @wiki_approval_data[:approval]

    # status check
    if approval.released?
      return render_error :status => :unprocessable_entity, :message => l(:wiki_approval_unable_start_status, :status => l("wiki_approval_workflow.status.#{approval.status}"))
    end

    steps = params[:steps]
    # JSON-Array (API):
    steps = steps.group_by { |s| s["step"].to_s } if steps.is_a?(Array)
    # no empty users
    steps_params = steps.transform_values { |users| users.reject { |u| u["principal_id"].blank? } }

    # Globale doublicat users
    if duplicate_users?(steps_params)
      if api_request?
        render_error :status => :unprocessable_entity, :message => l(:wiki_approval_unable_start_user)
      else
        flash.now[:error] = l(:wiki_approval_unable_start_user)
        restore_form_data
        render
      end
      return
    end

    latest_notifiable_step = nil

    ActiveRecord::Base.transaction do
      # if approval is not saved
      @wiki_approval_data[:approval].status ||= :pending
      @wiki_approval_data[:approval].author_id ||= User.current.id
      @wiki_approval_data[:approval].save! if @wiki_approval_data[:approval].new_record?

      # is already pending, for later mail
      approval_was_already_pending = (approval.status == 'pending')

      # save Steps
      steps_params.each do |step_nr, users|
        # Collect all user_ids for this step group
        user_ids = users.map { |u| u[:principal_id].to_i }
        # Delete all steps for this step_nr that are not in the submitted user_ids
        approval.approval_steps.where(step: step_nr).where.not(principal_id: user_ids).destroy_all

        approval.update(note: params[:note], author_id: User.current.id)

        # step_type from the first
        step_type = users.dig(0, :step_typ).presence || 'or'

        # create new users for this step
        users.each do |user_data|
          principal_object = User.find_by(id: user_data[:principal_id]) || Group.find_by(id: user_data[:principal_id])
          step_record = approval.approval_steps.for_principal(principal_object).find_or_initialize_by(step: step_nr)

          # Only set status to :unstarted if current status !approved
          step_record.step_status = :unstarted if step_record.step_status.nil? || !step_record.step_status_approved?
          step_record.step_type = step_type

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
      @steps = @wiki_approval_data[:approval].approval_steps
    end

    # Send email after the transaction if step_nr was saved for it, or if the user was changed or is new
    WikiApprovalMailer.deliver_wiki_approval_step(approval, approval.wiki_page, User.current, latest_notifiable_step) if latest_notifiable_step

    respond_to do |format|
      format.html do
        redirect_to project_wiki_page_path(@project.identifier, @page.title, :version => @page.content.version)
      end
      format.api do
        @wiki_approval_data[:approval].reload
        render template: 'wiki_approval/status'
      end
    end
  end

  def grant
    @step = @wiki_approval_data[:step_approval]

    # Check if all is available
    return render_404 unless @step

    if request.put?

      params[:step_status] = 'approved' if params[:step_status].blank?
      return render_error :status => :unprocessable_entity unless params[:step_status] == 'rejected' || params[:step_status] == 'approved'
      return render_error :status => :unprocessable_entity, :message => l(:wiki_approval_unable_note) if params[:step_status] == 'rejected' && params[:note].blank?

      @step.update({step_status: params[:step_status], note: params[:note], principal: User.current}.compact)

      respond_to do |format|
        format.html do
          redirect_to project_wiki_page_path(@project.identifier, @page.title, version: @page.content.version)
        end
        format.json do
          @wiki_approval_data[:approval].reload
          @steps = @wiki_approval_data[:approval].approval_steps
          render template: 'wiki_approval/status'
        end
      end
    else
      respond_to do |format|
        format.js { render layout: false }
        format.json { render_404 }
      end
    end
  end

  def forward
    @step = @wiki_approval_data[:step_approval]
    return render_404 unless @step

    @approval_user_options = approval_user_options(@project, @page.content.author_id, :wiki_approval_forward)

    if request.put?

      return render_error :status => :unprocessable_entity, :message => l(:wiki_approval_unable_note) if params[:note].blank?

      principal_object = User.find_by(id: params[:principal_id]) || Group.find_by(id: params[:principal_id])
      return render_404 unless principal_object.present? && @approval_user_options.include?(principal_object)

      # duplicate users
      if WikiApprovalWorkflowStep.for_principal(principal_object).where(wiki_approval_workflow_id: @step.approval.id).exists?
        return render_error :status => :unprocessable_entity, :message => l(:wiki_approval_unable_start_user)
      end

      @step.update({note: params[:note], principal: principal_object}.compact)

      # notify users from the step
      WikiApprovalMailer.deliver_wiki_approval_step(@step.approval, @step.approval.wiki_page, User.current, @step.step)

      respond_to do |format|
        format.html do
          redirect_to project_wiki_page_path(@project.identifier, @page.title, version: @page.content.version)
        end
        format.json do
          @wiki_approval_data[:approval].reload
          @steps = @wiki_approval_data[:approval].approval_steps
          render template: 'wiki_approval/status'
        end
      end
    else
      respond_to do |format|
        format.js { render layout: false }
        format.json { render_404 }
      end
    end
  end

  def publish
    return render_403 if request.format.html?

    approval = WikiApprovalWorkflow.save_for_draft(
      page: @page,
      user: User.current,
      status: 'published',
      wiki_approval_data: @wiki_approval_data
    )

    case approval
    when :already_released
      return render_error status: :conflict
    when :approval_required
      return render_403
    end

    respond_to do |format|
      format.json do
        @wiki_approval_data[:approval].reload
        render template: 'wiki_approval/status'
      end
    end
  end

  # List users/groups with wiki_approval_grant permission
  def permissions
    return render_403 if request.format.html?

    all_permissions = Redmine::AccessControl
                        .permissions
                        .select { |p| p.project_module == :wiki_approval }
                        .map { |p| p.name.to_sym }

    # optional permissions from params
    permissions_to_check = Array(params[:permissions]).map(&:to_sym).presence || all_permissions

    principals = []

    @project.memberships.includes(:principal, :roles).each do |m|
      principal = m.principal
      next if principal.is_a?(User) && principal.admin?

      # all permissions from modul wiki_approval
      matched_permissions = (m.roles.flat_map { |r| Array(r.permissions).map(&:to_sym) }.uniq) & permissions_to_check

      next if matched_permissions.empty?

      principals << {
        id: principal.id,
        name: principal.name,
        type: principal.is_a?(Group) ? "Group" : "User",
        permissions: matched_permissions
      }
    end

    respond_to do |format|
      format.api do
        render json: {
          actors: principals
        }, status: :ok
      end
    end
  end

  # GET /projects/:project_id/wiki_approval.json
  def index
    use_session = !request.format.csv?
    remove_empty_params
    if @project
      deny_access unless User.current.allowed_to?(:view_wiki_pages, @project)
    end

    retrieve_default_query(use_session)
    retrieve_query(WikiApprovalQuery, use_session)

    sort_init 'title', 'asc'
    sort_update @query.sortable_columns

    @query.project = @project if @project
    statement = @query.statement
    base = @query.base_scope.where(statement)

    @entry_count = base.count
    @entry_pages = Paginator.new @entry_count, per_page_option, params['page']

    @records = base.
      order(sort_clause).
      limit(@entry_pages.per_page).
      offset(@entry_pages.offset)

    respond_to do |format|
      format.html
      format.json
    end
  end

  def history
    return render_403 if request.format.html?

    @workflow_count = @page.wiki_approval_workflows.count
    @workflow_pages = Paginator.new @workflow_count, per_page_option, params['page']

    @workflows = @page.wiki_approval_workflows.
      preload(:author, :approval_steps).
      reorder(id: :desc).
      limit(@workflow_pages.per_page).
      offset(@workflow_pages.offset).
      to_a

    respond_to do |format|
      format.json
    end
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
    return render_404 unless params[:title]

    @page = WikiPage.joins(:wiki)
                    .find_by(wikis: { project_id: @project.id }, title: params[:title])

    return render_404 unless @page

    # find conten version, for status
    if params[:version].present?
      @content = @page.content_for_version(params[:version].to_i)
      return render_404 unless @content
    else
      @content = @page.content
    end

    @page
  end

  def check_module_enabled
    render_403 unless RedmineWikiApproval::Settings.is_enabled? @project
  end

  def approval_user_options(project, autor_id, permission = :wiki_approval_grant)
    users  = []
    groups = []

    project.memberships.each do |m|
      # users
      if (u = m.user)
        next if u.id == autor_id

        users << u if u.allowed_to?(permission, project)
      end

      # groups
      if (p = m.principal).is_a?(Group)
        has_permission =
          p.memberships.where(project_id: project.id).any? do |gm|
            gm.roles.any? { |r| Array(r.permissions).include?(permission) }
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
    @steps = []
    params[:steps].each do |step_number, users|
      users.each do |u|
        @steps << WikiApprovalWorkflowStep.new(
          step: step_number.to_i,
          principal_id: u["principal_id"],
          step_type: u["step_typ"]
        )
      end
    end
    @approval_user_options = approval_user_options(@project, @page.content.author_id)
  end

  def retrieve_default_query(use_session)
    return if params[:query_id].present?
    return if api_request?
    return if params[:set_filter]

    if params[:without_default].present?
      params[:set_filter] = 1
      return
    end

    # Session-Query Handling (wenn man wiederkommt)
    if !params[:set_filter] && use_session && session[:wiki_approval_query]
      query_id, project_id = session[:wiki_approval_query].values_at(:id, :project_id)

      return if query_id &&
                project_id == @project&.id &&
                WikiApprovalQuery.exists?(id: query_id)
    end

    # Default Query?
    if default_query = WikiApprovalQuery.default(project: @project)
      params[:query_id] = default_query.id
    end
  end

  def remove_empty_params
    params.reject! { |_, v| v.blank? }
  end
end
