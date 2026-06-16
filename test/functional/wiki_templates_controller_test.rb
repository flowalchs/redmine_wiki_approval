# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class WikiTemplatesControllerTest < WikiApproval::Test::ControllerCase
  tests WikiController

  def setup
    super
    set_session_user(@jsmith)
  end

  def remove_template_edit_permission
    [@manager_role, @developer_role].each do |role|
      role.remove_permission! :wiki_template_edit
    end
    @manager_role.reload
    @developer_role.reload
    User.current.reload
  end
  test "new to edit no templates redirect" do
    post :new, params: { project_id: @project.id, title: 'newTitle' }, xhr: true

    assert_response :success
    expected_path = project_wiki_page_path(@project, 'NewTitle')
    assert_match expected_path, @response.body
  end

  test "show to edit no templates" do
    get :show, params: {project_id: @project.identifier, id: 'NewTitle'}
    assert_response :success

    assert_select 'h2', 'NewTitle'
    assert_select 'form#wiki_form[action=?]', project_wiki_page_path(@project, 'NewTitle')
    assert_select 'textarea#content_text', /NewTitle/
    assert_select 'input[name="_method"][value="put"]', 1
  end

  test "new redirect with templates" do
    create_wiki_tree(@project)
    @page = WikiPage.find_by(title: 'Project_1')
    @workflow = WikiApprovalWorkflow.find_by(page_id: @page.id)

    post :new, params: { project_id: @project.id, title: 'newTitle', rwa_template_id: @workflow.id }, xhr: true

    assert_response :success
    expected_path = project_wiki_page_path(@project, 'NewTitle', :rwa_template_id => @workflow.id)
    assert_match expected_path, @response.body
  end

  test "show to edit with templates" do
    create_wiki_tree(@project)
    @page = WikiPage.find_by(title: 'Project_1')
    @workflow = WikiApprovalWorkflow.find_by(page_id: @page.id)
    get :show, params: {project_id: @project.identifier, id: 'NewTitle', rwa_template_id: @workflow.id}
    assert_response :success

    assert_select 'textarea#content_text', /Test content template Project 1/
  end

  test "new to edit disable modul" do
    create_wiki_tree(@project)
    @project.disable_module! :wiki_approval
    @page = WikiPage.find_by(title: 'GlobTemplate_2')
    @workflow = WikiApprovalWorkflow.find_by(page_id: @page.id)

    get :show, params: {project_id: @project.identifier, id: 'NewTitle', rwa_template_id: @workflow.id}
    assert_response :success

    assert_select 'textarea#content_text', /NewTitle/
  end

  test "new to edit with templates global" do
    create_wiki_tree(@project)
    @page = WikiPage.find_by(title: 'GlobTemplate_2')
    @workflow = WikiApprovalWorkflow.find_by(page_id: @page.id)

    get :show, params: {project_id: @project.identifier, id: 'NewTitle', rwa_template_id: @workflow.id}
    assert_response :success

    assert_select 'textarea#content_text', /Test content template GlobTemplate 2/
  end

  test "new to edit with templates project manager" do
    create_wiki_tree(@project)
    @page = WikiPage.find_by(title: 'ManagerProject_1')
    @workflow = WikiApprovalWorkflow.find_by(page_id: @page.id)

    get :show, params: {project_id: @project.identifier, id: 'NewTitle', rwa_template_id: @workflow.id}
    assert_response :success

    assert_select 'textarea#content_text', /Test content template ManagerProject 1/
  end

  test "new to edit with templates roles" do
    create_wiki_tree(@project)
    @page = WikiPage.find_by(title: 'Manager_first')
    @workflow = WikiApprovalWorkflow.find_by(page_id: @page.id)

    get :show, params: {project_id: @project.identifier, id: 'NewTitle', rwa_template_id: @workflow.id}
    assert_response :success

    assert_select 'textarea#content_text', /Test content template Manager first/
  end

  test "new to edit other project create templates" do
    create_wiki_tree(@project2)
    @page = WikiPage.find_by(title: 'GlobTemplate_2')
    @workflow = WikiApprovalWorkflow.find_by(page_id: @page.id)

    get :show, params: {project_id: @project.identifier, id: 'NewTitle', rwa_template_id: @workflow.id}
    assert_response :success

    assert_select 'textarea#content_text', /Test content template GlobTemplate 2/
  end

  test "save template templates with no permission" do
    remove_template_edit_permission
    assert_raises(ActiveRecord::RecordInvalid) do
      create_page(@project.wiki, "templates")
    end
  end

  test "save template header global roles project with no permission" do
    wiki = @project.wiki
    template = create_page(wiki, "templates")
    remove_template_edit_permission
    assert_raises(ActiveRecord::RecordInvalid) do
      create_page(wiki, "Global", parent: template)
    end
    assert_raises(ActiveRecord::RecordInvalid) do
      create_page(wiki, "Project", parent: template)
    end
    assert_raises(ActiveRecord::RecordInvalid) do
      create_page(wiki, "Roles", parent: template)
    end
  end

  test "save template header subprojects with no permission" do
    wiki = @project.wiki
    template = create_page(wiki, "templates")
    project_n = create_page(wiki, "Project", parent: template)
    remove_template_edit_permission
    assert_raises(ActiveRecord::RecordInvalid) do
      create_page(wiki, @project.identifier, parent: project_n)
    end
  end

  test "save template global roles project with no permission" do
    wiki = @project.wiki
    template = create_page(wiki, "templates")
    global    = create_page(wiki, "Global", parent: template)
    project_n = create_page(wiki, "Project", parent: template)
    subproject = create_page(wiki, @project.identifier, parent: project_n)
    roles_n   = create_page(wiki, "Roles", parent: template)
    manager2 = create_page(wiki, "Manager", parent: roles_n)
    remove_template_edit_permission
    assert_raises(ActiveRecord::RecordInvalid) do
      create_page(wiki, "GlobTemplate 1", parent: global)
    end
    assert_raises(ActiveRecord::RecordInvalid) do
      create_page(wiki, "Project 1", parent: subproject)
    end
    assert_raises(ActiveRecord::RecordInvalid) do
      create_page(wiki, "Manager first", parent: manager2)
    end
  end

  test "save template roles name with no permission" do
    wiki = @project.wiki
    template = create_page(wiki, "templates")
    roles_n   = create_page(wiki, "Roles", parent: template)
    remove_template_edit_permission
    assert_raises(ActiveRecord::RecordInvalid) do
      create_page(wiki, "Manager", parent: roles_n)
    end
  end

  test "save template project roles names with no permission" do
    wiki = @project.wiki
    template = create_page(wiki, "templates")
    project_n = create_page(wiki, "Project", parent: template)
    subproject = create_page(wiki, @project.identifier, parent: project_n)
    remove_template_edit_permission
    assert_raises(ActiveRecord::RecordInvalid) do
      create_page(wiki, "Role-1", parent: subproject)
    end
  end

  test "save template project roles template with no permission" do
    wiki = @project.wiki
    template = create_page(wiki, "templates")
    project_n = create_page(wiki, "Project", parent: template)
    subproject = create_page(wiki, @project.identifier, parent: project_n)
    role_node = create_page(wiki, "Role-1", parent: subproject)
    remove_template_edit_permission
    assert_raises(ActiveRecord::RecordInvalid) do
      create_page(wiki, "Manager proj", parent: role_node)
    end
  end
end
