# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class WikiApprovalViewTest < WikiApproval::Test::ControllerCase
  tests WikiController

  def setup
    super
    @page = WikiPage.find(11)
    set_session_user(@jsmith)
  end

  test 'wiki page redirect to released version' do
    get :show, params: { project_id: @project.id, id: @page.title }

    assert_response :redirect
    assert_redirected_to "/projects/1/wiki/#{@page.title}/2"
  end

  test 'wiki page show released version' do
    get :show, params: { project_id: @project.id, id: @page.title, version: 2 }
    assert_response :success
    # link to draft version, under contextual
    assert_select 'div#content div.contextual a.icon.icon-workflows[href*="wiki/Page_with_sections/3"]'
    # closed badge
    assert_select 'div#content div.contextual span.badge.badge-status-closed'
    # no sidebar default value settings
    assert_select '#sidebar .approval', minimum: 0
  end

  test 'wiki page show pending version and sidebar' do
    get :show, params: { project_id: @project.id, id: @page.title, version: 3 }
    assert_response :success
    # link to draft version, under contextual
    assert_select 'div#content div.contextual a.icon.icon-workflows[href*="wiki/Page_with_sections/2"]'
    # open badge
    assert_select 'div#content div.contextual span.badge.badge-status-open'
    # workflow approval icon
    assert_select 'div#content div.contextual a.icon.icon-workflows[href*="wiki_approval/Page_with_sections"]'
    # sidebar
    assert_select '#sidebar .approval', minimum: 1
    # no workflow grant icon
    assert_select 'div#content div.contextual a.icon.icon-approval', count: 0
    # no workflow forward icon
    assert_select 'div#content div.contextual a.icon.icon-forward', count: 0
  end

  test 'wiki page show pending version and without sidebar setting update' do
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_sidebar_status] = ["", "draft"]

    get :show, params: { project_id: @project.id, id: @page.title, version: 3 }
    assert_response :success
    # link to draft version, under contextual
    assert_select 'div#content div.contextual a.icon.icon-workflows[href*="wiki/Page_with_sections/2"]'
    # open badge
    assert_select 'div#content div.contextual span.badge.badge-status-open'
    # workflow approval icon
    assert_select 'div#content div.contextual a.icon.icon-workflows[href*="wiki_approval/Page_with_sections"]'
    # sidebar
    assert_select '#sidebar .approval', minimum: 0
  end

  test 'wiki page show pending version and sidebar setting update' do
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_sidebar_status] = ["", "pending"]

    get :show, params: { project_id: @project.id, id: @page.title, version: 3 }
    assert_response :success
    # sidebar
    assert_select '#sidebar .approval', minimum: 1
  end

  test 'wiki page show pending version and without sidebar projectsetting update' do
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_sidebar_project] = 1
    setting = WikiApprovalSetting.find_by(project_id: @project.id)
    setting.wiki_sidebar_status = ['', 'draft']
    setting.save!

    get :show, params: { project_id: @project.id, id: @page.title, version: 3 }
    assert_response :success
    # sidebar
    assert_select '#sidebar .approval', minimum: 0
  end

  test 'wiki page show pending version and with sidebar projectsetting update' do
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_sidebar_project] = 1
    setting = WikiApprovalSetting.find_by(project_id: @project.id)
    setting.wiki_sidebar_status = ['', 'pending']
    setting.save!

    get :show, params: { project_id: @project.id, id: @page.title, version: 3 }
    assert_response :success
    # sidebar
    assert_select '#sidebar .approval', minimum: 1
  end

  test 'wiki page show pending version and grant forward' do
    set_session_user(@dlopper)
    get :show, params: { project_id: @project.id, id: @page.title, version: 3 }
    assert_response :success
    # workflow grant icon
    assert_select 'div#content div.contextual a.icon.icon-approval[href*="wiki_approval/Page_with_sections/grant"]'
    # workflow forward icon
    assert_select 'div#content div.contextual a.icon.icon-forward[href*="wiki_approval/Page_with_sections/forward"]'
    # sidebar default value
    assert_select '#sidebar .approval', minimum: 1
  end

  test 'wiki page Unauthorized pending version no permission draft view' do
    set_session_user(@dlopper)
    RedmineWikiApproval::Settings.stubs(:view_draft?).with(@project).returns(false)
    get :show, params: { project_id: @project.id, id: @page.title, version: 3 }
    assert_response :forbidden
  end

  test 'wiki page show draft version and badge' do
    content = @page.content
    content.text = "New Version"
    content.save!

    WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :draft,
      author_id: User.current.id
    )

    get :show, params: { project_id: @project.id, id: @page.title, version: @page.content.version }
    assert_response :success

    # link to published version, under contextual
    assert_select 'div#content div.contextual a.icon.icon-workflows[href*="wiki/Page_with_sections/2"]'
    assert_match 'Draft', @response.body
    assert_match 'Published version', @response.body

    # open badge
    assert_select 'div#content div.contextual span.badge.badge-status-locked'
  end

  test 'wiki page show reject version and badge' do
    content = @page.content
    content.text = "New Version"
    content.save!

    WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :rejected,
      author_id: User.current.id
    )

    get :show, params: { project_id: @project.id, id: @page.title, version: @page.content.version }
    assert_response :success

    # link to published version, under contextual
    assert_select 'div#content div.contextual a.icon.icon-workflows[href*="wiki/Page_with_sections/2"]'
    assert_match 'Rejected', @response.body
    assert_match 'Published version', @response.body

    # open badge
    assert_select 'div#content div.contextual span.badge.badge-private'
  end

  test 'wiki delete page also approval' do
    # any workflows?
    approvals = WikiApprovalWorkflow.where(page_id: @page.id)
    assert approvals.any?
    approvals.each do |workflow|
      assert_not_equal 0, workflow.approval_steps.count
      assert_not_equal 0, workflow.approval_statuses.count
    end

    delete :destroy, params: { project_id: @project.id, id: @page.title, version: @page.content.version }
    assert_response :redirect

    approvals.reload
    assert_equal 0, approvals.count
    approvals.each do |workflow|
      assert_equal 0, workflow.approval_steps.count
      assert_equal 0, workflow.approval_statuses.count
    end
  end

  test 'wiki delete content version also approval' do
    # any workflows?
    approvals = WikiApprovalWorkflow.where(page_id: @page.id, version: @page.content.version)
    assert approvals.any?
    approvals.each do |workflow|
      assert_not_equal 0, workflow.approval_steps.count
      assert_not_equal 0, workflow.approval_statuses.count
    end

    delete :destroy_version, params: { project_id: @project.id, id: @page.title, version: @page.content.version }
    assert_response :redirect

    approvals.reload
    assert_equal 0, approvals.count
    approvals.each do |workflow|
      assert_equal 0, workflow.approval_steps.count
      assert_equal 0, workflow.approval_statuses.count
    end
  end

  test 'wiki page show redirect to version withoud approval' do
    @page = WikiPage.find(1)
    @page.content.attributes = {
      text: "New Version without approval in any version befor",
      comments: "Added via test",
      author_id: 1
    }
    @page.content.save!

    WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :draft,
      author_id: User.current.id
    )

    get :show, params: { project_id: @project.id, id: @page.title }
    assert_response :redirect
    assert_redirected_to "/projects/1/wiki/CookBook_documentation/3"

    # respons.body from version 3 test, after redirect rsponse.body is from original version
    get :show, params: { project_id: @project.id, id: @page.title, version: 3 }
    assert_response :success

    # link to view draft
    assert_select "a.icon-workflows[href='/projects/1/wiki/CookBook_documentation/4']" do |links|
      assert_match /View draft/, links.first.text
    end

    # no badge
    assert_select 'div#content div.contextual span.badge', false
    # sidebar no approval
    assert_select '#sidebar .approval', count: 0
    # no workflow grant icon
    assert_select 'div#content div.contextual a.icon.icon-approval', count: 0
    # no workflow forward icon
    assert_select 'div#content div.contextual a.icon.icon-forward', count: 0
  end
end
