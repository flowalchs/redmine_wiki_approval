# frozen_string_literal: true

class WikiApprovalQuery < Query
  self.queried_class = WikiPage
  self.view_permission = :view_wiki_pages

  def initialize(attributes=nil, *args)
    super
    self.filters ||= {}
  end

  def available_filters
    return @available_filters if @available_filters

    @available_filters = {}

    if project.nil?
      add_available_filter(
        "project_id",
        :type => :list, :values => lambda {
          valid_project_ids = Project.active.has_module(:wiki_approval)
                                    .joins(:wiki).pluck(:id).map(&:to_s)
          project_values.select { |name, id| valid_project_ids.include?(id.to_s) }
        }
      )
    end

    # --- Wiki page title ---
    add_available_filter "title",
      type: :text,
      name: l(:field_title)

    # --- Workflow status ---
    add_available_filter "status",
      type: :list_optional,
      name: l(:label_status),
      values: lambda {
        WikiApprovalWorkflow.statuses.map { |k, v| [k, k.to_s] }
      }

    # --- Workflow Author ---
    add_available_filter "author_id",
      type: :list,
      name: l(:label_wiki_approval_starter),
      values: lambda {workflow_author_filter_values}

    # --- Workflow Step Status ---
    add_available_filter "step_status",
      type: :list_optional,
      name: l(:label_wiki_approval_step_status),
      values: lambda {
        WikiApprovalWorkflowStep.step_statuses.keys.map { |k| [k, k] }
      }

    # --- Principal (User/Group) ---
    add_available_filter "principal_id",
      type: :list_optional,
      name: l(:label_wiki_approval_step_principal),
      values: lambda {principal_filter_values}

    if project && !project.leaf?
      add_available_filter(
        "subproject_id",
        :type => :list_subprojects,
        :values => lambda {subproject_values}
      )
    end

    @available_filters
  end

  # ------------------------------------------
  # COLUMNS
  # ------------------------------------------
  def available_columns
    return @available_columns if @available_columns

    @available_columns = [
      QueryColumn.new(:title, sortable: "#{WikiPage.table_name}.title"),
      QueryColumn.new(:version, sortable: "w.version"),
      QueryColumn.new(:revision, sortable: "w.revision"),
      QueryColumn.new(:note, sortable: "w.note"),
      QueryColumn.new(:workflow_status, sortable: "w.status"),
      QueryColumn.new(:workflow_author_id, sortable: "w.author_id"),
      QueryColumn.new(:workflow_updated_at, sortable: "w.updated_at"),
      QueryColumn.new(:workflow_step_status, sortable: "ws.step_status"),
      QueryColumn.new(:workflow_step_principal_id, sortable: "ws.principal_id")
    ]
  end

  # ------------------------------------------
  # SQL (Redmine ruft das für die List ab)
  # ------------------------------------------
  def statement
    @filters_sql = super
    project_sql = project_statement
    [@filters_sql, project_sql].compact.join(" AND ")
  end

  # ------------------------------------------
  # FROM + JOINs für deinen Index
  # ------------------------------------------
  def base_scope
    scope = WikiPage
      .preload(
        :parent,                # WikiPage => [:parent]
        wiki: :project,
        current_wiki_aw: [:author, { approval_steps: :principal }]
      )
      .joins(wiki: :project)
      .joins("INNER JOIN wiki_contents wc ON wc.page_id = wiki_pages.id")

    # only if needed, where or order
    if @filters_sql.to_s.include?("w.") || @filters_sql.to_s.include?("ws.")
      scope = scope.joins("LEFT JOIN wiki_approval_workflows w ON w.current_page_id = wiki_pages.id")
    end
    if @filters_sql.to_s.include?("ws.")
      scope = scope.joins("LEFT JOIN wiki_approval_workflow_steps ws ON ws.wiki_approval_workflow_id = w.id")
                   .distinct
    end
    scope
  end

  def sql_for_status_field(field, operator, value)
    int_values = value.filter_map { |v| WikiApprovalWorkflow.statuses[v] }
    sql_for_field(field, operator, int_values, "w", "status")
  end

  def sql_for_author_id_field(field, operator, value)
    values = Array(value).flatten.map(&:to_s)
    sql_for_field(field, operator, values, "w", "author_id")
  end

  def sql_for_title_field(field, operator, value)
    values = Array(value).flatten.map(&:to_s)
    sql_for_field(field, operator, values, "wiki_pages", "title")
  end

  def sql_for_step_status_field(field, operator, value)
    int_values = value.filter_map { |v| WikiApprovalWorkflowStep.step_statuses[v] }
    sql_for_field(field, operator, int_values, "ws", "step_status")
  end

  def sql_for_principal_id_field(field, operator, value)
    expanded_ids = Array(value).flatten.map(&:to_s)

    target_user_ids = []
    target_user_ids << User.current.id if expanded_ids.delete("me")

    all_ids = expanded_ids.grep(/\A\d+\z/).map(&:to_i).uniq

    users = User.where(id: all_ids).to_a

    group_ids_from_users = users.flat_map do |u|
      permitted_group_ids_for_user(
        u,
        :wiki_approval_start,
        allowed_project_ids
      )
    end

    final_ids = (all_ids + target_user_ids + group_ids_from_users).uniq.compact
    sql_for_field(field, operator, final_ids, "ws", "principal_id")
  end

  def sql_for_project_id_field(field, operator, value)
    values = Array(value).map(&:to_s).reject(&:blank?)

    # Identifier in IDs
    project_ids = Project.where(id: values).or(Project.where(identifier: values)).pluck(:id)

    # if no ids where found, no result
    project_ids = [-1] if project_ids.empty?

    sql_for_field(field, operator, project_ids, "projects", "id")
  end

  private

  def allowed_project_ids
    if project
      [project.id] + project.descendants.pluck(:id)
    else
      Project.visible.pluck(:id)
    end
  end

  def workflow_author_filter_values
    values = []
    values << ["<< #{l(:label_me)} >>", "me"] if User.current.logged?

    # user for wiki_approval_start
    values +=
      User.active
          .where(type: 'User')
          .select { |u| allowed_project_ids.any? { |pid| u.allowed_to?(:wiki_approval_start, Project.find(pid)) } }
          .sort_by(&:name)
          .map { |u| [u.name, u.id.to_s] }

    values
  end

  def principal_filter_values
    values = []
    values << ["<< #{l(:label_me)} >>", "me"] if User.current.logged?

    principals = Principal.active.select do |p|
      principal_has_permission?(p, :wiki_approval_start, allowed_project_ids)
    end

    values + principals.sort_by(&:name).map { |p| [p.name, p.id.to_s] }
  end

  def principal_has_permission?(principal, permission, project_ids)
    case principal
    when User
      project_ids.any? do |pid|
        principal.allowed_to?(permission, Project.find(pid))
      end

    when Group
      principal.memberships.where(project_id: project_ids).any? do |membership|
        membership.roles.any? do |role|
          role.permissions.include?(permission)
        end
      end

    else
      false
    end
  end

  def permitted_group_ids_for_user(user, permission, project_ids)
    # groups from user
    user_group_ids = user.groups.pluck(:id)
    return [] if user_group_ids.empty?

    # Groups that are members of the project AND have authorized roles
    Member.joins(:roles)
          .where(
            project_id: project_ids,
            user_id: user_group_ids
          )
          .select { |m| m.roles.any? { |r| r.permissions.include?(permission) } }
          .map(&:user_id)
          .uniq
  end
end
