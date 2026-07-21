# frozen_string_literal: true

class WikiApprovalQuery < Query
  self.queried_class = WikiPage
  self.view_permission = :view_wiki_pages

  def initialize(attributes=nil, *args)
    super
    self.filters ||= {}
  end

  def default_columns_names
    @default_columns_names ||= [
      :project, :title, :page_parent, :content_version, :approved_revision, :content_updated_on,
      :workflow_status, :workflow_author, :workflow_users
    ]
  end

  def default_sort_criteria
    [['project', 'asc'], ['page_parent', 'asc'], ['title', 'asc']]
  end

  def wiki_pages(options = {})
    order_option = [group_by_sort_order, options[:order]].flatten.reject(&:blank?)

    sql = statement

    active_columns = column_names.presence || default_columns_names
    needs_steps  = active_columns.include?(:workflow_users) || active_columns.include?(:workflow_author)
    needs_principal = active_columns.include?(:workflow_users)
    needs_watchers = active_columns.include?(:watchers)

    current_aw_includes = []
    current_aw_includes << :author if active_columns.any? do |c|
      [:workflow_author, :workflow_users].include?(c)
    end

    approved_aw_includes = []
    approved_aw_includes << :author if active_columns.any? do |c|
      [:approved_revision].include?(c)
    end

    current_aw_chain  = current_aw_includes.empty? ? :current_wiki_aw  : { current_wiki_aw:  current_aw_includes }
    approved_aw_chain = approved_aw_includes.empty? ? :approved_wiki_aw : { approved_wiki_aw: approved_aw_includes }

    extra_w  = order_option.to_s.include?("w.")
    extra_wa = order_option.to_s.include?("wa.")
    extra_ws = order_option.to_s.include?("ws.")

    needs_content_author = active_columns.include?(:last_updated_by)
    content_preload = needs_content_author ? { content_without_text: :author } : :content_without_text

    if needs_ws?
      ids = base_scope(extra_w: extra_w, extra_wa: extra_wa, extra_ws: extra_ws)
              .where(sql)
              .select("DISTINCT wiki_pages.id")
      scope = WikiPage
        .where(id: ids)
        .includes(:parent, wiki: :project)
        .includes(content_preload)
        .includes(current_aw_chain)
        .includes(approved_aw_chain)
        .order(order_option)
        .limit(options[:limit])
        .offset(options[:offset])
    else
      scope = base_scope(extra_w: extra_w, extra_wa: extra_wa, extra_ws: extra_ws)
        .includes(:parent, :content_without_text, wiki: :project)
        .includes(content_preload)
        .includes(current_aw_chain)
        .includes(approved_aw_chain)
        .where(sql)
        .order(order_option)
        .limit(options[:limit])
        .offset(options[:offset])
    end

    if needs_steps
      preload_hash =
        if needs_principal
          { approval_steps: :principal }
        else
          :approval_steps
        end

      scope = scope.preload(
        current_wiki_aw: preload_hash
      )
    end
    scope = scope.preload(:watcher_users) if needs_watchers

    scope
  rescue ::ActiveRecord::StatementInvalid => e
    raise StatementInvalid.new(e.message)
  end

  def wiki_page_count
    sql = statement
    scope = base_scope.where(sql)
    scope = scope.distinct if needs_ws?
    needs_ws? ? WikiPage.where(id: scope.select("wiki_pages.id")).count : scope.count
  rescue ::ActiveRecord::StatementInvalid => e
    raise StatementInvalid.new(e.message)
  end

  def wiki_page_count_by_group
    return nil unless grouped?

    sql = statement
    group_sql = group_by_column.instance_variable_get(:@groupable)
    group_sql = group_by_column.sortable if group_sql == true

    scope = base_scope.where(sql)
    scope = scope.joins("LEFT JOIN wiki_approval_workflows w ON w.current_page_id = wiki_pages.id") if group_sql.to_s.include?("w.")
    scope = scope.joins("LEFT JOIN wiki_approval_workflows wa ON wa.approved_page_id = wiki_pages.id") if group_sql.to_s.include?("wa.")
    scope = scope.joins("LEFT JOIN wiki_approval_workflow_steps ws ON ws.wiki_approval_workflow_id = w.id") if group_sql.to_s.include?("ws.")

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
      name: l(:label_wiki_approval_status),
      values: lambda {
        WikiApprovalWorkflow.statuses.map { |k, v| [k, k.to_s] }
      }

    # --- Workflow Author ---
    add_available_filter "author_id",
      type: :list,
      name: l(:label_wiki_approval_starter),
      values: lambda {author_filter_values(:wiki_approval_start)}

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

    # --- Watchers ---
    add_available_filter "watcher_id",
      type: :list,
      name: l(:field_watcher),
      values: lambda { watcher_filter_values }

    # --- Parent page title ---
    add_available_filter "parent_title",
      type: :text,
      name: l(:field_parent_title)

    # --- Created on ---
    add_available_filter "created_on",
      type: :date_past,
      name: l(:field_created_on)

    # --- Updated on (wiki_content) ---
    add_available_filter "updated_on",
      type: :date_past,
      name: l(:field_updated_on)

    # --- Locked ---
    add_available_filter "locked",
      type: :list,
      name: l(:label_board_locked),
      values: [[l(:general_text_yes), '1'], [l(:general_text_no), '0']]

    # --- Updated by (wiki_content author of last version) ---
    add_available_filter "last_updated_by",
      type: :list,
      name: l(:field_last_updated_by),
      values: lambda { author_filter_values(:edit_wiki_pages) }

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
      QueryColumn.new(:workflow_author, sortable: "w.author_id", caption: :label_wiki_approval_starter),
      QueryColumn.new(:workflow_users, sortable: false, caption: :label_wiki_approval_workflow),
      QueryColumn.new(:watchers, sortable: false, caption: :label_wiki_page_watchers),
      QueryColumn.new(:last_updated_by, sortable: "wc.author_id", caption: :field_last_updated_by),
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
  def base_scope(extra_w: false, extra_wa: false, extra_ws: false)
    scope = WikiPage
      .joins(wiki: :project)
      .joins("INNER JOIN wiki_contents wc ON wc.page_id = wiki_pages.id")
      .joins("LEFT JOIN wiki_pages parents_wiki_pages ON parents_wiki_pages.id = wiki_pages.parent_id")

    needs_w_join  = needs_w?  || extra_w || needs_ws? || extra_ws
    needs_ws_join = needs_ws? || extra_ws
    needs_wa_join = needs_wa? || extra_wa

    scope = scope.joins("LEFT JOIN wiki_approval_workflows w ON w.current_page_id = wiki_pages.id") if needs_w_join
    scope = scope.joins("LEFT JOIN wiki_approval_workflow_steps ws ON ws.wiki_approval_workflow_id = w.id") if needs_ws_join
    scope = scope.joins("LEFT JOIN wiki_approval_workflows wa ON wa.approved_page_id = wiki_pages.id") if needs_wa_join

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

  def sql_for_parent_title_field(field, operator, value)
    sql_for_field(field, operator, value, "parents_wiki_pages", "title")
  end

  def sql_for_created_on_field(field, operator, value)
    sql_for_field(field, operator, value, "wiki_pages", "created_on")
  end

  def sql_for_updated_on_field(field, operator, value)
    sql_for_field(field, operator, value, "wc", "updated_on")
  end

  def sql_for_locked_field(field, operator, value)
    bool_values = value.map { |v| v == '1' }
    sql_for_field(field, operator, bool_values, "wiki_pages", "protected")
  end

  def sql_for_last_updated_by_field(field, operator, value)
    user_ids = value.map { |v| v == 'me' ? User.current.id.to_s : v }
    sql_for_field(field, operator, user_ids, "wc", "author_id")
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

  def sql_for_watcher_id_field(field, operator, value)
    db_table = Watcher.table_name
    "#{WikiPage.table_name}.id #{operator == '=' ? 'IN' : 'NOT IN'} (
    SELECT #{db_table}.watchable_id FROM #{db_table}
    WHERE #{db_table}.watchable_type = 'WikiPage'
    AND #{db_table}.user_id IN (#{value.join(',')})
  )"
  end

  private

  def needs_w?
    @filters_sql.to_s.include?("w.") ||
    sort_criteria.to_s.include?("w.") ||
    group_by_column&.instance_variable_get(:@groupable).to_s.include?("w.")
  end

  def needs_ws?
    @filters_sql.to_s.include?("ws.") ||
    sort_criteria.to_s.include?("ws.") ||
    group_by_column&.instance_variable_get(:@groupable).to_s.include?("ws.")
  end

  def needs_wa?
    @filters_sql.to_s.include?("wa.") ||
    sort_criteria.to_s.include?("wa.") ||
    group_by_column&.instance_variable_get(:@groupable).to_s.include?("wa.")
  end

  def allowed_project_ids
    if project
      [project.id] + project.descendants.pluck(:id)
    else
      Project.visible.pluck(:id)
    end
  end

  def author_filter_values(permission = nil)
    values = []
    values << ["<< #{l(:label_me)} >>", "me"] if User.current.logged?

    if permission
      # Direkt über DB: User die in mindestens einem Projekt die Permission haben
      permission_name = permission.to_s
      role_ids = Role.where("permissions LIKE ?", "%#{permission_name}%").pluck(:id)

      user_ids = Member.joins(:roles)
                      .where(project_id: allowed_project_ids)
                      .where(member_roles: { role_id: role_ids })
                      .pluck(:user_id)
                      .uniq

      users = User.active.where(type: 'User', id: user_ids)
    else
      users = User.active.where(type: 'User')
    end

    values + users.sorted.map { |u| [u.name, u.id.to_s] }
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

  def watcher_filter_values
    values = []
    values << ["<< #{l(:label_me)} >>", User.current.id.to_s] if User.current.logged?
    values += User.active.where(type: 'User').sorted.map { |u| [u.name, u.id.to_s] }
    values
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
