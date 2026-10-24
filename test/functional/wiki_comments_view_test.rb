# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class WikiCommentsViewTest < WikiApproval::Test::ControllerCase
  tests WikiController

  def setup
    super
    @page = WikiPage.find(11)
    set_session_user(@jsmith)
  end

  def grant(*permissions)
    permissions.each { |p| @manager_role.add_permission! p }
  end

  test 'wiki page without comment permission has no panel' do
    get :show, params: { project_id: @project.id, id: @page.title, version: 2 }
    assert_response :success
    assert_select '#wiki-comments', 0
    assert_select '#rwa-comments-sidebar', 0
    assert_select 'script[src*="wiki_approval_comments"]', 0
  end

  test 'wiki page with view permission shows panel without forms' do
    grant :wiki_comments_view
    WikiApprovalComment.create!(page_id: @page.id, author: @dlopper, text: 'Visible comment', quote: 'Section')

    get :show, params: { project_id: @project.id, id: @page.title, version: 2 }
    assert_response :success
    assert_select 'div[data-controller="wiki-comments"] div.wiki.wiki-page'
    assert_select '#wiki-comments .rwa-thread[data-quote="Section"]', 1
    assert_select '#wiki-comments .rwa-comment-body', text: /Visible comment/
    assert_select '#wiki-comments form', 0
    assert_select '#sidebar #rwa-comments-sidebar .rwa-comments-authors li', 1
    assert_select 'script[type="module"][src*="wiki_approval_comments"]', 1
  end

  test 'wiki page with add permission shows forms' do
    grant :wiki_comments_view, :wiki_comments_add

    get :show, params: { project_id: @project.id, id: @page.title, version: 2 }
    assert_response :success
    assert_select '#wiki-comments form.rwa-page-comment-form'
    assert_select '#wiki-comments template[data-wiki-comments-target="inlineForm"]'
    assert_select 'div[data-controller="wiki-comments"][data-wiki-comments-can-add-value="true"]'
  end

  test 'older version hides newer threads and shows them open until resolved' do
    grant :wiki_comments_view
    old = WikiApprovalComment.create!(page_id: @page.id, author: @dlopper, text: 'Old thread', version: 1)
    old.resolve!(@jsmith, 3)
    WikiApprovalComment.create!(page_id: @page.id, author: @dlopper, text: 'New thread', version: 3)

    get :show, params: { project_id: @project.id, id: @page.title, version: 2 }
    assert_response :success
    assert_select '#wiki-comments .rwa-thread', 1
    assert_select '#wiki-comments .rwa-thread[data-status="open"] .rwa-comment-body', text: /Old thread/
    assert_select '#wiki-comments .rwa-newer-info', 1
    assert_select '#rwa-comments-sidebar .rwa-comments-summary li', text: /1 open comment/
  end

  test 'resolved threads are grouped by revision in panel and sidebar' do
    grant :wiki_comments_view
    WikiApprovalComment.create!(page_id: @page.id, author: @dlopper, text: 'Earlier', version: 1).resolve!(@jsmith, 1)
    WikiApprovalComment.create!(page_id: @page.id, author: @dlopper, text: 'Current', version: 1).resolve!(@jsmith, 2)

    get :show, params: { project_id: @project.id, id: @page.title, version: 2 }
    assert_response :success
    assert_select '#wiki-comments h4.rwa-group-current', 1
    assert_select '#wiki-comments h4.rwa-group-earlier', 1
    assert_select '#wiki-comments .rwa-thread[data-group="current"]', 1
    assert_select '#rwa-comments-sidebar a[data-rwa-group="current"]', text: /1 resolved in this revision/
    assert_select '#rwa-comments-sidebar a[data-rwa-group="earlier"]', text: /1 resolved in earlier revisions/
  end

  test 'project setting disables comments' do
    grant :wiki_comments_view
    with_wiki_approval_settings(wiki_approval_settings_comments: 'project') do
      with_project_wiki_settings(@project, wiki_comments: false) do
        get :show, params: { project_id: @project.id, id: @page.title, version: 2 }
        assert_response :success
        assert_select '#wiki-comments', 0
      end
    end
  end
end
