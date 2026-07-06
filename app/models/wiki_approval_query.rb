# frozen_string_literal: true

class WikiApprovalQuery < Query
  self.queried_class = WikiPage
  self.view_permission = :view_wiki_pages

  def initialize(attributes=nil, *args)
    super
    self.filters ||= {}
  end

  # Standard-Spalten beim ersten Aufruf, bevor User eigene Auswahl speichert
  def default_columns_names
    @default_columns_names ||= [
      :project, :title, :page_parent, :content_version, :approved_revision, :content_updated_on,
      :workflow_status, :workflow_updated_at, :workflow_author, :workflow_users
    ]
  end

  def default_sort_criteria
    [['project', 'asc'], ['page_parent', 'asc'], ['title', 'asc']]
  end

  def wiki_pages(options = {})
    order_option = [group_by_sort_order, (options[:order] || sort_criteria.sort_clause(@available_columns))].flatten.reject(&:blank?)

    base_scope
      .where(statement)
      .order(order_option)
      .limit(options[:limit])
      .offset(options[:offset])
  rescue ::ActiveRecord::StatementInvalid => e
    raise StatementInvalid.new(e.message)
  end

  def wiki_page_count
    base_scope.where(statement).count
  rescue ::ActiveRecord::StatementInvalid => e
    raise StatementInvalid.new(e.message)
  end

  def wiki_page_count_by_group
    return nil unless grouped?

    group_sql = group_by_column.instance_variable_get(:@groupable)
    group_sql = group_by_column.sortable if group_sql == true

    scope = base_scope.where(statement)

    # ensure joins are present for group_sql
    if group_sql.to_s.include?("w.")
      scope = scope.joins("LEFT JOIN wiki_approval_workflows w ON w.current_page_id = wiki_pages.id")
    end
    if group_sql.to_s.include?("wa.")
      scope = scope.joins("LEFT JOIN wiki_approval_workflows wa ON wa.approved_page_id = wiki_pages.id")
    end
    if group_sql.to_s.include?("ws.")
      scope = scope.joins("LEFT JOIN wiki_approval_workflow_steps ws ON ws.wiki_approval_workflow_id = w.id")
    end
    if group_sql.to_s.include?("parents_wiki_pages.")
      scope = scope.joins("LEFT JOIN wiki_pages parents_wiki_pages ON parents_wiki_pages.id = wiki_pages.parent_id")
    end

    scope.group(group_sql).count
  rescue ::ActiveRecord::StatementInvalid => e
    raise StatementInvalid.new(e.message)
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
      QueryColumn.new(:project, sortable: "#{Project.table_name}.name", groupable: "#{Project.table_name}.name"),
      QueryColumn.new(:title, sortable: "#{WikiPage.table_name}.title"),
      QueryColumn.new(:created_on, sortable: "#{WikiPage.table_name}.created_on", caption: :field_created_on),
      QueryColumn.new(:protected, sortable: "#{WikiPage.table_name}.protected", groupable: "#{WikiPage.table_name}.protected", caption: :label_board_locked),
      QueryColumn.new(:page_parent, sortable: "CASE WHEN wiki_pages.parent_id IS NULL THEN 0 ELSE 1 END, parents_wiki_pages.title",
                      groupable: "parents_wiki_pages.title", caption: :field_parent_title),
      QueryColumn.new(:content_comments,  sortable: "wc.comments", caption: :field_comments),
      QueryColumn.new(:content_updated_on, sortable: "wc.updated_on", caption: :field_updated_on),
      QueryColumn.new(:content_version, sortable: "wc.version", caption: :field_version),
      QueryColumn.new(:approved_revision, sortable: "wa.version", caption: :label_revision),
      QueryColumn.new(:workflow_status, sortable: "w.status", groupable: "w.status", caption: :field_status),
      QueryColumn.new(:workflow_updated_at, sortable: "w.updated_at", caption: :field_workflow_updated_at),
      QueryColumn.new(:workflow_author, sortable: false, caption: :label_wiki_approval_starter),
      QueryColumn.new(:workflow_users, sortable: false, caption: :label_wiki_approval_workflow),
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
        :parent,
        :content,
        wiki: :project,
        current_wiki_aw: [:author, { approval_steps: :principal }],
        approved_wiki_aw: [:author, { approval_steps: :principal }]
      )
      .joins(wiki: :project)
      .joins("INNER JOIN wiki_contents wc ON wc.page_id = wiki_pages.id")
      .joins("LEFT JOIN wiki_pages parents_wiki_pages ON parents_wiki_pages.id = wiki_pages.parent_id")

    needs_w  = @filters_sql.to_s.include?("w.") ||
               sort_criteria.to_s.include?("w.") ||
               group_by_column&.instance_variable_get(:@groupable).to_s.include?("w.")

    needs_ws = @filters_sql.to_s.include?("ws.") ||
               sort_criteria.to_s.include?("ws.") ||
               group_by_column&.instance_variable_get(:@groupable).to_s.include?("ws.")

    needs_wa = @filters_sql.to_s.include?("wa.") ||
               sort_criteria.to_s.include?("wa.") ||
               group_by_column&.instance_variable_get(:@groupable).to_s.include?("wa.")

    if needs_w
      scope = scope.joins("LEFT JOIN wiki_approval_workflows w ON w.current_page_id = wiki_pages.id")
    end
    if needs_ws
      scope = scope.joins("LEFT JOIN wiki_approval_workflow_steps ws ON ws.wiki_approval_workflow_id = w.id")
                   .distinct
    end
    if needs_wa
      scope = scope.joins("LEFT JOIN wiki_approval_workflows wa ON wa.approved_page_id = wiki_pages.id")
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
