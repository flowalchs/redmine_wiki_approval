# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class WikiApprovalCommentsControllerTest < WikiApproval::Test::ControllerCase
  tests WikiApprovalCommentsController

  def setup
    super
    [@manager_role, @developer_role].each do |role|
      role.add_permission! :wiki_comments_view
      role.add_permission! :wiki_comments_add
    end
    set_session_user(@jsmith)
    @page = WikiPage.find(11)
  end

  def json
    JSON.parse(@response.body)
  end

  def thread_params(extra = {})
    { project_id: @project.id, title: @page.title }.merge(extra)
  end

  test 'index renders panel and sidebar as json' do
    WikiApprovalComment.create!(page_id: @page.id, author: @jsmith, text: 'Hello panel', quote: 'section')

    get :index, params: thread_params, xhr: true
    assert_response :success
    assert_equal 1, json['open']
    assert_includes json['panel'], 'Hello panel'
    assert_includes json['panel'], 'data-quote="section"'
    assert_includes json['sidebar'], 'rwa-comments-sidebar'
  end

  test 'create inline comment with start version' do
    assert_difference 'WikiApprovalComment.count', 1 do
      post :create, params: thread_params(text: 'Inline', quote: 'Section', prefix: 'pre', suffix: 'suf', version: 2), xhr: true
    end
    assert_response :created

    comment = WikiApprovalComment.last
    assert_equal json['id'], comment.id
    assert_equal 'Section', comment.quote
    assert_equal 2, comment.version
    assert_equal @jsmith, comment.author
  end

  test 'create falls back to current version' do
    post :create, params: thread_params(text: 'Page comment', version: 999), xhr: true
    assert_response :created
    assert_equal @page.content.version, WikiApprovalComment.last.version
    assert_not WikiApprovalComment.last.inline?
  end

  test 'create reply' do
    thread = WikiApprovalComment.create!(page_id: @page.id, author: @dlopper, text: 'Thread')

    post :create, params: thread_params(text: 'Reply', parent_id: thread.id), xhr: true
    assert_response :created
    assert_equal [thread.id], WikiApprovalComment.where(text: 'Reply').pluck(:parent_id)
  end

  test 'create reply to other page is not found' do
    other = WikiApprovalComment.create!(page_id: 1, author: @dlopper, text: 'Other page')

    post :create, params: thread_params(text: 'Reply', parent_id: other.id), xhr: true
    assert_response :not_found
  end

  test 'create without text returns errors' do
    post :create, params: thread_params(text: ''), xhr: true
    assert_response :unprocessable_entity
    assert json['errors'].any?
  end

  test 'create without permission is forbidden' do
    @manager_role.remove_permission! :wiki_comments_add
    post :create, params: thread_params(text: 'Nope'), xhr: true
    assert_response :forbidden
  end

  test 'disabled setting is forbidden' do
    with_wiki_approval_settings(wiki_approval_settings_comments: 'false') do
      get :index, params: thread_params, xhr: true
      assert_response :forbidden
    end
  end

  test 'update own comment' do
    comment = WikiApprovalComment.create!(page_id: @page.id, author: @jsmith, text: 'Old')

    patch :update, params: thread_params(id: comment.id, text: 'New'), xhr: true
    assert_response :success
    assert_equal 'New', comment.reload.text
  end

  test 'update and destroy foreign comment needs manage permission' do
    comment = WikiApprovalComment.create!(page_id: @page.id, author: @dlopper, text: 'Foreign')

    patch :update, params: thread_params(id: comment.id, text: 'Changed'), xhr: true
    assert_response :forbidden
    delete :destroy, params: thread_params(id: comment.id), xhr: true
    assert_response :forbidden

    @manager_role.add_permission! :wiki_comments_manage
    delete :destroy, params: thread_params(id: comment.id), xhr: true
    assert_response :success
    assert_not WikiApprovalComment.exists?(comment.id)
  end

  test 'destroy thread removes replies' do
    thread = WikiApprovalComment.create!(page_id: @page.id, author: @jsmith, text: 'Thread')
    WikiApprovalComment.create!(page_id: @page.id, author: @dlopper, text: 'Reply', parent: thread)

    assert_difference 'WikiApprovalComment.count', -2 do
      delete :destroy, params: thread_params(id: thread.id), xhr: true
    end
  end

  test 'resolve stores viewed version and reopen clears it' do
    thread = WikiApprovalComment.create!(page_id: @page.id, author: @dlopper, text: 'Thread', version: 2)

    put :resolve, params: thread_params(id: thread.id, version: 3, resolved: 'true'), xhr: true
    assert_response :success
    thread.reload
    assert thread.resolved?
    assert_equal 3, thread.resolved_version
    assert_equal @jsmith, thread.resolved_by
    assert_equal 1, json['resolved']

    put :resolve, params: thread_params(id: thread.id, resolved: 'false'), xhr: true
    assert thread.reload.open?
    assert_nil thread.resolved_version
  end

  test 'replies cannot be resolved' do
    thread = WikiApprovalComment.create!(page_id: @page.id, author: @jsmith, text: 'Thread')
    reply = WikiApprovalComment.create!(page_id: @page.id, author: @jsmith, text: 'Reply', parent: thread)

    put :resolve, params: thread_params(id: reply.id), xhr: true
    assert_response :forbidden
  end
end
