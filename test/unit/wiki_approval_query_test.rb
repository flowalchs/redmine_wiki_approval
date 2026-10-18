# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class WikiApprovalQueryTest < WikiApproval::Test::UnitCase
  # wiki pages of project 1 (ecookbook): 1, 2, 4, 5, 6, 10, 11, 12
  PROJECT_PAGE_IDS = [1, 2, 4, 5, 6, 10, 11, 12].freeze

  def setup
    super
    User.current = @jsmith

    # page 1: current draft by admin
    @draft = create_workflow(1, status: :draft, author: @admin)
    # page 2: pending by jsmith with two pending steps (dlopper and group)
    @pending = create_workflow(2, status: :pending, author: @jsmith,
                                  steps: [[@dlopper, :pending], [@group, :pending]])
    # page 10: released by admin
    @released = create_workflow(10, status: :released, author: @admin)
    # page 11: fixtures, pending by jsmith, step dlopper pending, approved revision 1

    Member.create!(principal: @group, project: @project, role_ids: [@developer_role.id])
    Watcher.create!(watchable: WikiPage.find(11), user: @jsmith)
  end

  # ------------------------------------------
  # defaults
  # ------------------------------------------

  def test_default_columns_names_from_settings
    with_wiki_approval_settings(wiki_approval_settings_default_wiki_columns: %w[title workflow_status]) do
      assert_equal [:title, :workflow_status], WikiApprovalQuery.new.default_columns_names
    end
  end

  def test_default_columns_names_fallback_when_setting_is_empty
    with_wiki_approval_settings(wiki_approval_settings_default_wiki_columns: ['']) do
      assert_equal WikiApprovalQuery::DEFAULT_COLUMNS, WikiApprovalQuery.new.default_columns_names
    end
    with_wiki_approval_settings(wiki_approval_settings_default_wiki_columns: nil) do
      query = WikiApprovalQuery.new
      assert_equal WikiApprovalQuery::DEFAULT_COLUMNS, query.default_columns_names
      assert_equal WikiApprovalQuery::DEFAULT_COLUMNS, query.columns.map(&:name)
    end
  end

  def test_default_sort_criteria
    query = WikiApprovalQuery.new
    assert_equal [['project', 'asc'], ['page_parent', 'asc'], ['title', 'asc']], query.sort_criteria.to_a
  end

  def test_default_returns_nil_without_setting
    with_wiki_approval_settings(wiki_approval_settings_default_wiki_query: '') do
      assert_nil WikiApprovalQuery.default
    end
  end

  def test_default_returns_public_global_query
    query = create_query(visibility: Query::VISIBILITY_PUBLIC)
    with_wiki_approval_settings(wiki_approval_settings_default_wiki_query: query.id.to_s) do
      assert_equal query, WikiApprovalQuery.default
    end
  end

  def test_default_ignores_missing_private_and_project_queries
    private_query = create_query(visibility: Query::VISIBILITY_PRIVATE, user: @admin)
    project_query = create_query(visibility: Query::VISIBILITY_PUBLIC, project: @project)

    [private_query.id, project_query.id, 999_999].each do |id|
      with_wiki_approval_settings(wiki_approval_settings_default_wiki_query: id.to_s) do
        assert_nil WikiApprovalQuery.default, "query #{id} must not be the default"
      end
    end
  end

  # ------------------------------------------
  # available filters / columns
  # ------------------------------------------

  def test_available_filters_without_project
    query = WikiApprovalQuery.new
    expected = %w[project_id author_id title status workflow_author_id step_status principal_id
                  watcher_id parent_title created_on updated_on locked updated_by]
    assert_equal expected.sort, query.available_filters.keys.sort
  end

  def test_available_filters_with_project
    query = WikiApprovalQuery.new(project: @project)
    assert_not_includes query.available_filters.keys, 'project_id'
    assert_includes query.available_filters.keys, 'subproject_id'

    leaf = WikiApprovalQuery.new(project: @project3)
    assert_not_includes leaf.available_filters.keys, 'subproject_id'
  end

  def test_project_filter_values_only_contain_projects_with_module_and_wiki
    values = WikiApprovalQuery.new.available_filters['project_id'][:values].map(&:last).map(&:to_s)
    assert_includes values, @project.id.to_s
    # project 2 has a wiki, but no wiki_approval module
    assert_not_includes values, @project2.id.to_s
  end

  def test_available_columns
    names = WikiApprovalQuery.new.available_columns.map(&:name)
    expected = [:project, :title, :created_on, :protected, :page_parent, :content_comments, :content_updated_on,
                :content_version, :approved_revision, :workflow_status, :workflow_updated_at, :workflow_author,
                :workflow_users, :watchers, :updated_by, :author]
    assert_equal expected, names
  end

  # ------------------------------------------
  # visibility
  # ------------------------------------------

  def test_project_query_returns_pages_of_project
    assert_equal PROJECT_PAGE_IDS, query_page_ids({}, project: @project)
  end

  def test_global_query_for_admin_returns_all_pages
    User.current = @admin
    assert_equal WikiPage.pluck(:id).sort, query_page_ids
  end

  def test_query_without_permission_returns_nothing
    User.current = User.anonymous
    Role.anonymous.remove_permission!(:view_wiki_pages)
    Role.non_member.remove_permission!(:view_wiki_pages)
    query = build_query
    assert_equal 0, query.wiki_page_count
    assert_empty query.wiki_pages
  end

  def test_project_query_does_not_return_other_projects
    query = build_query({}, project: @project)
    assert_not_includes query.wiki_pages.map { |p| p.wiki.project_id }, @project2.id
  end

  # ------------------------------------------
  # filters
  # ------------------------------------------

  def test_filter_project_id_by_id_and_identifier
    User.current = @admin
    assert_equal PROJECT_PAGE_IDS, query_page_ids(filter('project_id', '=', [@project.id.to_s]))
    assert_equal PROJECT_PAGE_IDS, query_page_ids(filter('project_id', '=', [@project.identifier]))
    assert_equal [], query_page_ids(filter('project_id', '=', ['unknown']))
  end

  def test_filter_subproject_id
    query = build_query(filter('subproject_id', '!*', ['']), project: @project)
    assert_equal PROJECT_PAGE_IDS, query.wiki_pages.map(&:id).sort
  end

  def test_filter_title
    assert_equal [11], query_page_ids(filter('title', '~', ['with_sections']), project: @project)
    assert_equal [1, 2, 4, 10, 11], query_page_ids(filter('title', '!~', ['Child']), project: @project)
  end

  def test_filter_title_with_alias_like_value_does_not_add_joins
    query = build_query(filter('title', '~', ['www.ws.wa.']), project: @project)
    assert_not query.send(:needs_w?)
    assert_not query.send(:needs_ws?)
    assert_not query.send(:needs_wa?)
    assert_equal 0, query.wiki_page_count
  end

  def test_filter_parent_title
    assert_equal [5, 6], query_page_ids(filter('parent_title', '=', ['Another_page']), project: @project)
    assert_equal [1, 2, 10, 11], query_page_ids(filter('parent_title', '!*', ['']), project: @project)
  end

  def test_filter_locked
    assert_equal [1], query_page_ids(filter('locked', '=', ['1']), project: @project)
    assert_equal PROJECT_PAGE_IDS - [1], query_page_ids(filter('locked', '=', ['0']), project: @project)
  end

  def test_filter_status
    assert_equal [2, 11], query_page_ids(filter('status', '=', ['pending']), project: @project)
    assert_equal [1, 2, 11], query_page_ids(filter('status', '=', ['draft', 'pending']), project: @project)
    # like core, "!" includes pages without workflow
    assert_equal [1, 4, 5, 6, 10, 12], query_page_ids(filter('status', '!', ['pending']), project: @project)
    assert_equal [1, 2, 10, 11], query_page_ids(filter('status', '*', ['']), project: @project)
    assert_equal [4, 5, 6, 12], query_page_ids(filter('status', '!*', ['']), project: @project)
  end

  def test_filter_workflow_author_id
    assert_equal [2, 11], query_page_ids(filter('workflow_author_id', '=', ['me']), project: @project)
    assert_equal [1, 10], query_page_ids(filter('workflow_author_id', '=', [@admin.id.to_s]), project: @project)
  end

  def test_filter_step_status
    assert_equal [2, 11], query_page_ids(filter('step_status', '=', ['pending']), project: @project)
    assert_equal [2, 11], query_page_ids(filter('step_status', '*', ['']), project: @project)
    assert_equal [], query_page_ids(filter('step_status', '=', ['approved']), project: @project)
  end

  def test_filter_principal_id
    assert_equal [2, 11], query_page_ids(filter('principal_id', '=', [@dlopper.id.to_s]), project: @project)

    User.current = @dlopper
    assert_equal [2, 11], query_page_ids(filter('principal_id', '=', ['me']), project: @project)
  end

  def test_filter_principal_id_includes_steps_of_users_groups
    # group membership from setup is inherited by the group users
    group_user = @group.users.first

    assert_equal [2], query_page_ids(filter('principal_id', '=', [group_user.id.to_s]), project: @project)
    assert_equal [2], query_page_ids(filter('principal_id', '=', [@group.id.to_s]), project: @project)
  end

  def test_filter_author_id
    # first content version of page 1 is from jsmith, of page 2, 4, 11 from admin
    assert_equal [1], query_page_ids(filter('author_id', '=', ['me']), project: @project)
    assert_equal [2, 4, 11], query_page_ids(filter('author_id', '=', [@admin.id.to_s]), project: @project)
  end

  def test_filter_updated_by
    WikiContent.find_by(page_id: 2).update_column(:author_id, @jsmith.id)
    assert_equal [2], query_page_ids(filter('updated_by', '=', ['me']), project: @project)
    assert_equal PROJECT_PAGE_IDS - [2], query_page_ids(filter('updated_by', '=', [@admin.id.to_s]), project: @project)
  end

  def test_filter_watcher_id
    assert_equal [11], query_page_ids(filter('watcher_id', '=', [@jsmith.id.to_s]), project: @project)
    assert_equal [11], query_page_ids(filter('watcher_id', '=', ['me']), project: @project)
    assert_equal PROJECT_PAGE_IDS - [11], query_page_ids(filter('watcher_id', '!', [@jsmith.id.to_s]), project: @project)
  end

  def test_filter_watcher_id_quotes_values
    query = build_query(filter('watcher_id', '=', ['0) OR (1=1']), project: @project)
    assert_not_includes query.statement, 'IN (0) OR (1=1)'
    assert_includes query.statement, ActiveRecord::Base.connection.quote_string('0) OR (1=1')
  end

  def test_filter_created_on
    WikiPage.where(id: 2).update_all(created_on: 2.days.ago)
    WikiPage.where.not(id: 2).update_all(created_on: 1.year.ago)
    assert_equal [2], query_page_ids(filter('created_on', '>t-', ['7']), project: @project)
  end

  def test_filter_updated_on
    WikiContent.where(page_id: 11).update_all(updated_on: 2.days.ago)
    WikiContent.where.not(page_id: 11).update_all(updated_on: 1.year.ago)
    assert_equal [11], query_page_ids(filter('updated_on', '>t-', ['7']), project: @project)
  end

  def test_combined_filters
    params = filter('status', '=', ['pending'])
    params[:f] << 'principal_id'
    params[:op]['principal_id'] = '='
    params[:v]['principal_id'] = [@dlopper.id.to_s]
    params[:f] << 'title'
    params[:op]['title'] = '~'
    params[:v]['title'] = ['Another']
    assert_equal [2], query_page_ids(params, project: @project)
  end

  # ------------------------------------------
  # counts
  # ------------------------------------------

  def test_count_matches_records_for_all_filters
    filters = [
      filter('status', '=', ['pending']),
      filter('step_status', '=', ['pending']),
      filter('principal_id', '*', ['']),
      filter('watcher_id', '=', ['me']),
      filter('author_id', '=', ['me']),
      filter('locked', '=', ['0']),
      filter('title', '~', ['Child'])
    ]
    filters.each do |params|
      query = build_query(params, project: @project)
      assert_equal query.wiki_pages.size, query.wiki_page_count, "count mismatch for #{params[:f]}"
    end
  end

  def test_step_join_counts_every_page_only_once
    # page 2 has two steps
    query = build_query(filter('step_status', '=', ['pending']), project: @project)
    assert_equal 2, query.wiki_page_count
    assert_equal [2, 11], query.wiki_pages.map(&:id).sort
  end

  def test_group_counts_with_step_join_are_distinct
    params = filter('step_status', '=', ['pending']).merge(group_by: 'workflow_status')
    query = build_query(params, project: @project)
    assert_equal({ WikiApprovalWorkflow.statuses['pending'] => 2 }, query.wiki_page_count_by_group)
  end

  # ------------------------------------------
  # grouping
  # ------------------------------------------

  def test_group_counts_sum_up_for_all_groupable_columns
    query = WikiApprovalQuery.new
    query.groupable_columns.each do |column|
      grouped = build_query({ group_by: column.name.to_s }, project: @project)
      counts = grouped.wiki_page_count_by_group
      assert_equal grouped.wiki_page_count, counts.values.sum, "group count mismatch for #{column.name}"
      assert_equal grouped.wiki_page_count, grouped.wiki_pages.size
    end
  end

  def test_group_by_workflow_status
    counts = build_query({ group_by: 'workflow_status' }, project: @project).wiki_page_count_by_group
    statuses = WikiApprovalWorkflow.statuses
    assert_equal 1, counts[statuses['draft']]
    assert_equal 2, counts[statuses['pending']]
    assert_equal 1, counts[statuses['released']]
    assert_equal 4, counts[nil]
  end

  def test_group_by_author
    counts = build_query({ group_by: 'author' }, project: @project).wiki_page_count_by_group
    assert_equal({ @jsmith.id => 1, @admin.id => 3, nil => 4 }, counts)
  end

  def test_group_by_project
    User.current = @admin
    counts = build_query({ group_by: 'project' }).wiki_page_count_by_group
    assert_equal 8, counts[@project.name]
  end

  def test_not_grouped_returns_nil
    assert_nil build_query({}, project: @project).wiki_page_count_by_group
  end

  def test_grouped_records_are_ordered_by_group
    pages = build_query({ group_by: 'workflow_status' }, project: @project).wiki_pages
    statuses = pages.map { |p| p.current_wiki_aw&.status_before_type_cast }
    assert_equal statuses.compact.sort, statuses.compact
  end

  # ------------------------------------------
  # sorting
  # ------------------------------------------

  def test_sort_by_all_sortable_columns
    WikiApprovalQuery.new.available_columns.select(&:sortable?).each do |column|
      %w[asc desc].each do |direction|
        query = build_query({ sort: "#{column.name}:#{direction}" }, project: @project)
        assert_equal PROJECT_PAGE_IDS, query.wiki_pages(order: query.sort_clause).map(&:id).sort,
                     "sort by #{column.name} #{direction}"
      end
    end
  end

  def test_sort_by_all_sortable_columns_with_step_filter
    WikiApprovalQuery.new.available_columns.select(&:sortable?).each do |column|
      params = filter('step_status', '=', ['pending']).merge(sort: "#{column.name}:desc")
      query = build_query(params, project: @project)
      assert_equal [2, 11], query.wiki_pages(order: query.sort_clause).map(&:id).sort,
                   "sort by #{column.name} with step filter"
    end
  end

  def test_sort_by_title
    query = build_query({ sort: 'title:desc' }, project: @project)
    titles = query.wiki_pages(order: query.sort_clause).map(&:title)
    assert_equal titles.sort.reverse, titles
  end

  def test_sort_by_page_parent_desc_applies_to_parent_title
    query = build_query({ sort: 'page_parent:desc' }, project: @project)
    pages = query.wiki_pages(order: query.sort_clause).to_a
    with_parent = pages.select(&:parent_id)
    assert_equal pages.first(with_parent.size), with_parent
    parent_titles = with_parent.map { |p| p.parent.title }
    assert_equal parent_titles.sort.reverse, parent_titles
  end

  def test_sort_by_approved_revision
    query = build_query({ sort: 'approved_revision:desc' }, project: @project)
    pages = query.wiki_pages(order: query.sort_clause).to_a
    assert_includes pages.map(&:id), 11
  end

  def test_limit_and_offset
    query = build_query({ sort: 'title' }, project: @project)
    all = query.wiki_pages(order: query.sort_clause).map(&:id)
    assert_equal all[2, 3], query.wiki_pages(order: query.sort_clause, offset: 2, limit: 3).map(&:id)
  end

  # ------------------------------------------
  # columns / preloading
  # ------------------------------------------

  def test_all_columns_can_be_loaded
    names = WikiApprovalQuery.new.available_columns.map(&:name).map(&:to_s)
    query = build_query({ c: names }, project: @project)
    pages = query.wiki_pages.to_a
    page = pages.detect { |p| p.id == 2 }

    assert_equal PROJECT_PAGE_IDS, pages.map(&:id).sort
    assert_equal @pending, page.current_wiki_aw
    assert_equal 2, page.current_wiki_aw.approval_steps.size
    assert_equal @admin, page.author
    assert_equal 1, pages.detect { |p| p.id == 11 }.approved_wiki_aw.revision
    assert_equal [@jsmith], pages.detect { |p| p.id == 11 }.watcher_users.to_a
  end

  # ------------------------------------------
  # joins
  # ------------------------------------------

  def test_joins_only_for_needed_filters
    query = build_query({}, project: @project)
    assert_not query.send(:needs_w?)
    assert_not query.send(:needs_ws?)
    assert_not query.send(:needs_wcv1?)

    query = build_query(filter('status', '=', ['draft']), project: @project)
    assert query.send(:needs_w?)
    assert_not query.send(:needs_ws?)

    query = build_query(filter('principal_id', '*', ['']), project: @project)
    assert query.send(:needs_w?)
    assert query.send(:needs_ws?)

    query = build_query(filter('author_id', '=', ['me']), project: @project)
    assert query.send(:needs_wcv1?)
  end

  def test_joins_for_group_by
    assert build_query({ group_by: 'workflow_status' }, project: @project).send(:needs_w?)
    assert build_query({ group_by: 'author' }, project: @project).send(:needs_wcv1?)
    assert_not build_query({ group_by: 'project' }, project: @project).send(:needs_w?)
  end

  # ------------------------------------------
  # filter values
  # ------------------------------------------

  def test_principal_filter_values
    values = filter_values('principal_id')
    assert_equal ["<< #{I18n.t(:label_me)} >>", 'me'], values.first
    ids = values.map(&:last)
    assert_includes ids, @jsmith.id.to_s
    assert_includes ids, @dlopper.id.to_s
    assert_includes ids, @group.id.to_s
    assert_not_includes ids, @rhill.id.to_s
  end

  def test_principal_filter_values_without_permission
    [@manager_role, @developer_role].each { |role| role.remove_permission!(:wiki_approval_start) }
    assert_equal ['me'], filter_values('principal_id').map(&:last)
  end

  def test_workflow_author_filter_values
    ids = filter_values('workflow_author_id').map(&:last)
    assert_equal 'me', ids.first
    assert_includes ids, @jsmith.id.to_s
    assert_includes ids, @dlopper.id.to_s
    # groups are no workflow authors
    assert_not_includes ids, @group.id.to_s
  end

  def test_updated_by_filter_values
    @developer_role.remove_permission!(:edit_wiki_pages)
    ids = filter_values('updated_by').map(&:last)
    assert_includes ids, @jsmith.id.to_s
    assert_not_includes ids, @dlopper.id.to_s
  end

  def test_author_filter_values
    ids = filter_values('author_id').map(&:last)
    assert_equal ['me', @admin.id.to_s, @jsmith.id.to_s].sort, ids.sort
  end

  def test_watcher_filter_values
    ids = filter_values('watcher_id').map(&:last)
    assert_equal @jsmith.id.to_s, ids.first
    assert_includes ids, @dlopper.id.to_s
  end

  def test_filter_values_without_logged_user_have_no_me
    User.current = @admin
    query = WikiApprovalQuery.new(project: @project)
    User.current = User.anonymous
    assert_not_includes query.available_filters['status'][:values].map(&:last), 'me'
    %w[principal_id workflow_author_id author_id].each do |field|
      assert_not_includes query.available_filters[field][:values].map(&:last), 'me', field
    end
  end

  private

  # options instead of keyword arguments, ruby 2.7 would take a params hash as keywords
  def build_query(params = {}, options = {})
    query = WikiApprovalQuery.new(name: '_', project: options[:project])
    query.build_from_params(ActionController::Parameters.new({ set_filter: '1' }.merge(params)).permit!)
    assert query.valid?, query.errors.full_messages.join(', ')
    query
  end

  def query_page_ids(params = {}, options = {})
    build_query(params, options).wiki_pages.map(&:id).sort
  end

  def filter(field, operator, values)
    { f: [field], op: { field => operator }, v: { field => values } }
  end

  def filter_values(field)
    WikiApprovalQuery.new(project: @project).available_filters[field][:values]
  end

  def create_query(visibility:, user: @jsmith, project: nil)
    WikiApprovalQuery.create!(name: "query #{visibility}", user: user, project: project, visibility: visibility)
  end

  def create_workflow(page_id, status:, author:, steps: [])
    page = WikiPage.find(page_id)
    workflow = WikiApprovalWorkflow.create!(
      page_id: page.id,
      version: page.content.version,
      status: status,
      author_id: author.id
    )
    steps.each do |principal, step_status|
      step = WikiApprovalWorkflowStep.new(
        approval: workflow, step: 1, step_type: :or, step_status: step_status, principal: principal
      )
      # keep the given step status, without workflow transitions
      step.define_singleton_method(:check_next_step) { nil }
      step.save!
    end
    workflow.reload
  end
end
