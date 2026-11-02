# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class WikiApprovalQueryControllerTest < WikiApproval::Test::ControllerCase
  tests WikiApprovalController

  def setup
    super
    set_session_user(@jsmith)
  end

  test 'index with project denies access without view_wiki_pages' do
    set_session_user(@rhill)
    Role.non_member.remove_permission!(:view_wiki_pages)

    get :index, params: { project_id: @project.id }
    assert_response :forbidden
  end

  test 'index lists wiki pages of projects without the wiki approval module' do
    assert_not @project2.module_enabled?(:wiki_approval)
    page = WikiPage.joins(:wiki).where(wikis: { project_id: @project2.id }).first

    get :index, params: { set_filter: 1, f: ['project_id'], op: { project_id: '=' }, v: { project_id: [@project2.id.to_s] } }
    assert_response :success
    assert_select 'table.list tbody td.title', text: page.title

    get :index, params: { project_id: @project2.id }
    assert_response :success
    assert_select 'table.list tbody td.title', text: page.title
  end

  test 'index with filter' do
    get :index, params: {
      project_id: @project.id, set_filter: 1,
      f: ['status'], op: { status: '=' }, v: { status: ['pending'] }
    }
    assert_response :success
    assert_select 'table.list tbody tr', count: 1
    assert_select 'table.list tbody td.title', text: 'Page_with_sections'
  end

  test 'index with all columns renders every column' do
    columns = WikiApprovalQuery.new.available_columns.map(&:name).map(&:to_s)
    get :index, params: { project_id: @project.id, set_filter: 1, c: columns }

    assert_response :success
    columns.each do |column|
      assert_select "table.list thead th", { minimum: 1 }, column
      assert_select "table.list tbody td.#{column}", { minimum: 1 }, column
    end
  end

  test 'index sorted by title desc' do
    get :index, params: { project_id: @project.id, set_filter: 1, c: ['title'], sort: 'title:desc' }
    assert_response :success

    titles = css_select('table.list tbody td.title').map { |td| td.text.strip }
    assert_equal titles.sort.reverse, titles
    assert_select 'table.list thead th a.sort.desc', text: 'Title'
  end

  test 'index uses sort criteria of saved query' do
    query = WikiApprovalQuery.create!(
      name: 'sorted', user: @jsmith, project: @project, visibility: Query::VISIBILITY_PRIVATE,
      column_names: [:title], sort_criteria: [['title', 'desc']]
    )
    get :index, params: { project_id: @project.id, query_id: query.id }
    assert_response :success

    titles = css_select('table.list tbody td.title').map { |td| td.text.strip }
    assert_equal titles.sort.reverse, titles
  end

  test 'index grouped by workflow status' do
    get :index, params: { project_id: @project.id, set_filter: 1, group_by: 'workflow_status', c: ['title'] }
    assert_response :success

    assert_select 'tr.group', minimum: 2
    assert_select 'tr.group span.count', text: '1'
  end

  test 'index grouped by author shows name and count' do
    get :index, params: { project_id: @project.id, set_filter: 1, group_by: 'author', c: ['title', 'author'] }
    assert_response :success

    assert_select 'tr.group span.name', text: @admin.name
    assert_select 'tr.group span.count', minimum: 1
    assert_select 'table.list tbody td.author a', minimum: 1
  end

  test 'index pagination' do
    with_settings per_page_options: '2,25' do
      get :index, params: { project_id: @project.id, set_filter: 1, per_page: 2, page: 2 }
    end
    assert_response :success
    assert_select 'table.list tbody tr', count: 2
    assert_select 'span.pagination span.items', text: '(3-4/8)'
  end

  test 'index applies global default query' do
    query = WikiApprovalQuery.create!(
      name: 'default', user: @admin, visibility: Query::VISIBILITY_PUBLIC,
      filters: { 'status' => { operator: '=', values: ['pending'] } }
    )
    with_wiki_approval_settings(wiki_approval_settings_default_wiki_query: query.id.to_s) do
      get :index, params: { project_id: @project.id }
      assert_response :success
      assert_select 'h2', text: 'default'
      assert_select 'table.list tbody tr', count: 1
    end
  end

  test 'index ignores deleted default query' do
    with_wiki_approval_settings(wiki_approval_settings_default_wiki_query: '999999') do
      get :index, params: { project_id: @project.id }
      assert_response :success
      assert_select 'table.list tbody tr', count: 8
    end
  end

  test 'index ignores private default query' do
    query = WikiApprovalQuery.create!(name: 'private', user: @admin, visibility: Query::VISIBILITY_PRIVATE)
    with_wiki_approval_settings(wiki_approval_settings_default_wiki_query: query.id.to_s) do
      get :index, params: { project_id: @project.id }
      assert_response :success
      assert_select 'h2', text: 'private', count: 0
    end
  end

  test 'index without_default skips default query' do
    query = WikiApprovalQuery.create!(
      name: 'default', user: @admin, visibility: Query::VISIBILITY_PUBLIC,
      filters: { 'status' => { operator: '=', values: ['pending'] } }
    )
    with_wiki_approval_settings(wiki_approval_settings_default_wiki_query: query.id.to_s) do
      get :index, params: { project_id: @project.id, without_default: 1 }
      assert_response :success
      assert_select 'table.list tbody tr', count: 8
    end
  end

  test 'index with invalid filter renders errors' do
    get :index, params: {
      project_id: @project.id, set_filter: 1,
      f: ['created_on'], op: { created_on: '>t-' }, v: { created_on: ['abc'] }
    }
    assert_response :success
    assert_select '#errorExplanation'
    assert_select 'table.list', count: 0
  end

  test 'index sidebar lists saved queries' do
    WikiApprovalQuery.create!(name: 'my wiki query', user: @jsmith, project: @project,
                              visibility: Query::VISIBILITY_PRIVATE)
    get :index, params: { project_id: @project.id }
    assert_response :success
    assert_select '#sidebar a.query', text: 'my wiki query'
  end
end

class WikiApprovalQueriesControllerTest < WikiApproval::Test::ControllerCase
  tests QueriesController

  def setup
    super
    set_session_user(@jsmith)
  end

  test 'create query redirects to project wiki list' do
    post :create, params: {
      project_id: @project.id, type: 'WikiApprovalQuery', query: { name: 'new wiki query' },
      f: ['status'], op: { status: '=' }, v: { status: ['pending'] }
    }
    query = WikiApprovalQuery.find_by(name: 'new wiki query')
    assert_not_nil query
    assert_redirected_to "/projects/#{@project.identifier}/wiki_approval?query_id=#{query.id}"
  end

  test 'create global query redirects to global wiki list' do
    set_session_user(@admin)
    post :create, params: {
      type: 'WikiApprovalQuery', query: { name: 'global wiki query', visibility: '2' }, query_is_for_all: 1
    }
    query = WikiApprovalQuery.find_by(name: 'global wiki query')
    assert_not_nil query
    assert_redirected_to "/wiki_approval?query_id=#{query.id}"
  end
end
