# frozen_string_literal: true

class WikiApprovalCommentsController < ApplicationController
  accept_api_auth :index, :create, :update, :destroy, :resolve

  menu_item :wiki
  before_action :find_project
  before_action :check_enabled, :authorize
  before_action :find_page
  before_action :find_comment, only: [:update, :destroy, :resolve]

  helper :wiki_approval_icon
  helper :wiki_approval
  helper :wiki_approval_comments

  def index
    @comments = WikiApprovalComment.threads_for(@page)
    @comments = @comments.where(status: params[:status]) if WikiApprovalComment.statuses.key?(params[:status])

    api_request? ? render(action: 'index') : render_panel
  end

  def create
    @comment = WikiApprovalComment.new(page_id: @page.id, author: User.current)
    @comment.text = params[:text]

    parent_id = params[:parent_id].presence
    if parent_id
      @comment.parent = WikiApprovalComment.find_by(id: parent_id, page_id: @page.id)
      return render_404 unless @comment.parent
    else
      @comment.version = @version
      @comment.quote = params[:quote]
      @comment.prefix = params[:prefix]
      @comment.suffix = params[:suffix]
    end

    if @comment.save
      respond_with_comment(:created)
    else
      respond_with_errors
    end
  end

  def update
    return render_403 unless @comment.editable_by?(User.current, @project)

    @comment.text = params[:text]
    if @comment.save
      respond_with_comment
    else
      respond_with_errors
    end
  end

  def destroy
    return render_403 unless @comment.editable_by?(User.current, @project)

    @comment.destroy
    api_request? ? render_api_ok : render_panel
  end

  def resolve
    return render_403 unless @comment.resolvable_by?(User.current, @project)

    if ActiveModel::Type::Boolean.new.cast(params.fetch(:resolved, true))
      @comment.resolve!(User.current, @version)
    else
      @comment.reopen!(User.current, @version)
    end
    respond_with_comment
  end

  private

  def find_project
    @project = Project.find(params[:project_id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def check_enabled
    render_403 unless RedmineWikiApproval::Settings.comments_enabled?(@project) &&
                      User.current.allowed_to?(:view_wiki_pages, @project)
  end

  def find_page
    @page = @project.wiki&.find_page(params[:title])
    return render_404 unless @page&.content

    # viewed version (start or resolved version), fallback to the current version
    current = @page.content.version
    requested = params[:version].to_i
    @version = requested.between?(1, current) ? requested : current
  end

  def find_comment
    @comment = WikiApprovalComment.find_by(id: params[:id], page_id: @page.id)
    render_404 unless @comment
  end

  # api: rsb views, otherwise XHR from the stimulus controller
  def respond_with_comment(status = :ok)
    api_request? ? render(action: 'show', status: status) : render_panel(status)
  end

  def respond_with_errors
    return render_validation_errors(@comment) if api_request?

    render json: { errors: @comment.errors.full_messages }, status: :unprocessable_entity
  end

  # re-rendered panel and sidebar as json
  def render_panel(status = :ok)
    locals = { page: @page, project: @project, version: @version }.merge(WikiApprovalComment.version_data(@page, @version, reverse: User.current.wants_comments_in_reverse_order?))
    summary = locals[:summary]

    render status: status, json: {
      id: @comment&.id,
      open: summary[:open],
      resolved: summary[:resolved],
      panel: render_to_string(partial: 'wiki_approval_comments/panel', formats: [:html], locals: locals),
      sidebar: render_to_string(partial: 'wiki_approval_comments/sidebar', formats: [:html], locals: locals)
    }
  end
end
