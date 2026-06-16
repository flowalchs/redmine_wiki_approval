# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class WikiApprovalTest < WikiApproval::Test::IntegrationCase
  def setup
    super
    log_user('jsmith', 'jsmith')
    User.current = @jsmith
  end

  test "new wiki js no templates" do
    get "/projects/#{@project.identifier}/wiki/new", xhr: true, headers: { "HTTP_ACCEPT" => "text/javascript" }

    assert_response :success
    body = @response.body

    assert_includes body, 'New wiki page'
    assert_match /<form.*new_page/, body
    assert_no_match(/name="rwa_template_id"/, body)
  end

  test "new wiki js with templates" do
    create_wiki_tree(@project)
    get "/projects/#{@project.identifier}/wiki/new", xhr: true, headers: { "HTTP_ACCEPT" => "text/javascript" }

    assert_response :success
    html = ajax_html(@response.body)

    assert_select_in html, 'select#rwa_template_id' do
      assert_select 'option', 7
      assert_select 'option' do |elements|
        assert_equal 1, elements.count { |e| e.text.delete("\u00A0").strip.empty? }
      end
      assert_select 'option', text: 'GlobTemplate 1', count: 1
      assert_select 'option', text: 'GlobTemplate 2', count: 1
      assert_select 'option', text: 'Project 1', count: 1
      assert_select 'option', text: 'Projekt 2', count: 1
      assert_select 'option', text: 'ManagerProject 1', count: 1
      assert_select 'option', text: 'ManagerProject 2', count: 1
      assert_select 'option', text: 'Manager first', count: 0
      assert_select 'option', text: 'Manager second', count: 0
    end
  end

  test "new wiki js templates no global" do
    create_wiki_tree(@project)

    with_project_wiki_settings(@project,
      { wiki_templates: ['projects', 'roles'] }
    ) do
      get "/projects/#{@project.identifier}/wiki/new", xhr: true, headers: { "HTTP_ACCEPT" => "text/javascript" }

      assert_response :success
      html = ajax_html(@response.body)

      assert_select_in html, 'select#rwa_template_id' do
        assert_select 'option', 5
        assert_select 'option' do |elements|
          assert_equal 1, elements.count { |e| e.text.delete("\u00A0").strip.empty? }
        end
        assert_select 'option', text: 'GlobTemplate 1', count: 0
        assert_select 'option', text: 'GlobTemplate 2', count: 0
        assert_select 'option', text: 'Project 1', count: 1
        assert_select 'option', text: 'Projekt 2', count: 1
        assert_select 'option', text: 'ManagerProject 1', count: 1
        assert_select 'option', text: 'ManagerProject 2', count: 1
        assert_select 'option', text: 'Manager first', count: 0
        assert_select 'option', text: 'Manager second', count: 0
      end
    end
  end

  test "new wiki js templates no roles" do
    create_wiki_tree(@project)

    with_project_wiki_settings(@project,
      { wiki_templates: ['projects', 'global'] }
    ) do
      get "/projects/#{@project.identifier}/wiki/new", xhr: true, headers: { "HTTP_ACCEPT" => "text/javascript" }

      assert_response :success
      html = ajax_html(@response.body)

      assert_select_in html, 'select#rwa_template_id' do
        assert_select 'option', 7
        assert_select 'option' do |elements|
          assert_equal 1, elements.count { |e| e.text.delete("\u00A0").strip.empty? }
        end
        assert_select 'option', text: 'GlobTemplate 1', count: 1
        assert_select 'option', text: 'GlobTemplate 2', count: 1
        assert_select 'option', text: 'Project 1', count: 1
        assert_select 'option', text: 'Projekt 2', count: 1
        assert_select 'option', text: 'ManagerProject 1', count: 1
        assert_select 'option', text: 'ManagerProject 2', count: 1
        assert_select 'option', text: 'Manager first', count: 0
        assert_select 'option', text: 'Manager second', count: 0
      end
    end
  end

  test "new wiki js templates only project" do
    create_wiki_tree(@project)

    with_project_wiki_settings(@project,
      { wiki_templates: ['projects'] }
    ) do
      get "/projects/#{@project.identifier}/wiki/new", xhr: true, headers: { "HTTP_ACCEPT" => "text/javascript" }

      assert_response :success
      html = ajax_html(@response.body)

      assert_select_in html, 'select#rwa_template_id' do
        assert_select 'option', 5
        assert_select 'option' do |elements|
          assert_equal 1, elements.count { |e| e.text.delete("\u00A0").strip.empty? }
        end
        assert_select 'option', text: 'GlobTemplate 1', count: 0
        assert_select 'option', text: 'GlobTemplate 2', count: 0
        assert_select 'option', text: 'Project 1', count: 1
        assert_select 'option', text: 'Projekt 2', count: 1
        assert_select 'option', text: 'ManagerProject 1', count: 1
        assert_select 'option', text: 'ManagerProject 2', count: 1
        assert_select 'option', text: 'Manager first', count: 0
        assert_select 'option', text: 'Manager second', count: 0
      end
    end
  end

  test "new wiki js templates only roles" do
    create_wiki_tree(@project)

    with_project_wiki_settings(@project,
      { wiki_templates: ['roles'] }
    ) do
      get "/projects/#{@project.identifier}/wiki/new", xhr: true, headers: { "HTTP_ACCEPT" => "text/javascript" }

      assert_response :success
      html = ajax_html(@response.body)

      assert_select_in html, 'select#rwa_template_id' do
        assert_select 'option', 3
        assert_select 'option' do |elements|
          assert_equal 1, elements.count { |e| e.text.delete("\u00A0").strip.empty? }
        end
        assert_select 'option', text: 'GlobTemplate 1', count: 0
        assert_select 'option', text: 'GlobTemplate 2', count: 0
        assert_select 'option', text: 'Project 1', count: 0
        assert_select 'option', text: 'Projekt 2', count: 0
        assert_select 'option', text: 'ManagerProject 1', count: 0
        assert_select 'option', text: 'ManagerProject 2', count: 0
        assert_select 'option', text: 'Manager first', count: 1
        assert_select 'option', text: 'Manager second', count: 1
      end
    end
  end

  test "new wiki js with templates other project not enabled" do
    create_wiki_tree(@project)
    get "/projects/#{@project2.identifier}/wiki/new", xhr: true, headers: { "HTTP_ACCEPT" => "text/javascript" }

    assert_response :success
    html = ajax_html(@response.body)

    assert_no_match "rwa_template_id", html
  end

  test "new wiki js with templates other project as developer" do
    create_wiki_tree(@project)

    @project3.create_wiki(start_page: 'Wiki')
    @page = WikiPage.create!(wiki: @project3.wiki, title: 'Subproject_Page_test')
    WikiContent.create!(page: @page, text: 'content', author_id: 1, updated_on: Time.now)
    Member.create!(project: @project3, user: @jsmith, roles: [@developer_role])

    get "/projects/#{@project3.identifier}/wiki/new", xhr: true, headers: { "HTTP_ACCEPT" => "text/javascript" }

    assert_response :success
    html = ajax_html(@response.body)

    assert_select_in html, 'select#rwa_template_id' do
      assert_select 'option', 3
      assert_select 'option' do |elements|
        assert_equal 1, elements.count { |e| e.text.delete("\u00A0").strip.empty? }
      end
      assert_select 'option', text: 'GlobTemplate 1', count: 1
      assert_select 'option', text: 'GlobTemplate 2', count: 1
      assert_select 'option', text: 'Project 1', count: 0
      assert_select 'option', text: 'Projekt 2', count: 0
      assert_select 'option', text: 'ManagerProject 1', count: 0
      assert_select 'option', text: 'ManagerProject 2', count: 0
      assert_select 'option', text: 'Manager first', count: 0
      assert_select 'option', text: 'Manager second', count: 0
    end
  end

  test "new wiki js with templates other project as manager" do
    create_wiki_tree(@project)

    @project3.create_wiki(start_page: 'Wiki')
    @page = WikiPage.create!(wiki: @project3.wiki, title: 'Subproject_Page_test')
    WikiContent.create!(page: @page, text: 'content', author_id: 1, updated_on: Time.now)
    Member.create!(project: @project3, user: @jsmith, roles: [@manager_role])

    get "/projects/#{@project3.identifier}/wiki/new", xhr: true, headers: { "HTTP_ACCEPT" => "text/javascript" }

    assert_response :success
    html = ajax_html(@response.body)

    assert_select_in html, 'select#rwa_template_id' do
      assert_select 'option', 5
      assert_select 'option' do |elements|
        assert_equal 1, elements.count { |e| e.text.delete("\u00A0").strip.empty? }
      end
      assert_select 'option', text: 'GlobTemplate 1', count: 1
      assert_select 'option', text: 'GlobTemplate 2', count: 1
      assert_select 'option', text: 'Project 1', count: 0
      assert_select 'option', text: 'Projekt 2', count: 0
      assert_select 'option', text: 'ManagerProject 1', count: 0
      assert_select 'option', text: 'ManagerProject 2', count: 0
      assert_select 'option', text: 'Manager first', count: 1
      assert_select 'option', text: 'Manager second', count: 1
    end
  end

  test "new wiki js with templates other project as manager only project" do
    create_wiki_tree(@project)

    @project3.create_wiki(start_page: 'Wiki')
    @page = WikiPage.create!(wiki: @project3.wiki, title: 'Subproject_Page_test')
    WikiContent.create!(page: @page, text: 'content', author_id: 1, updated_on: Time.now)
    Member.create!(project: @project3, user: @jsmith, roles: [@manager_role])

    with_project_wiki_settings(@project3,
  { wiki_templates: ['projects'] }
    ) do
      get "/projects/#{@project3.identifier}/wiki/new", xhr: true, headers: { "HTTP_ACCEPT" => "text/javascript" }

      assert_response :success
      html = ajax_html(@response.body)

      assert_no_match "rwa_template_id", html
    end
  end

  test "new wiki js with templates disabled modul" do
    create_wiki_tree(@project)
    @project.disable_module! :wiki_approval
    get "/projects/#{@project.identifier}/wiki/new", xhr: true, headers: { "HTTP_ACCEPT" => "text/javascript" }

    assert_response :success
    html = ajax_html(@response.body)
    assert_no_match "rwa_template_id", html
  end

  test "new wiki open with template" do
    create_wiki_tree(@project)
    page = WikiPage.find_by(title: 'Project_1', wiki: @project.wiki)
    workflow = WikiApprovalWorkflow.find_by(page_id: page.id)&.latest_public_version
    get "/projects/#{@project.identifier}/wiki/withtemplate?rwa_template_id=#{workflow.id}", headers: { "HTTP_ACCEPT" => "text/javascript" }

    assert_response :success
    assert_select 'textarea#content_text' do |elements|
      assert_equal 'Test content template Project 1', elements.first.text.strip
    end
  end

  test "new wiki open with unknown template" do
    create_wiki_tree(@project)
    get "/projects/#{@project.identifier}/wiki/withtemplate?rwa_template_id=99999", headers: { "HTTP_ACCEPT" => "text/javascript" }

    assert_response :success
    assert_select 'textarea#content_text' do |elements|
      assert_match /withtemplate/i, elements.first.text.strip
    end
  end

  test "new wiki open with template not projects enabled" do
    create_wiki_tree(@project)
    page = WikiPage.find_by(title: 'Project_1', wiki: @project.wiki)
    workflow = WikiApprovalWorkflow.find_by(page_id: page.id)&.latest_public_version

    with_project_wiki_settings(@project,
  { wiki_templates: ['roles'] }
    ) do
      get "/projects/#{@project.identifier}/wiki/withtemplate?rwa_template_id=#{workflow.id}", headers: { "HTTP_ACCEPT" => "text/javascript" }

      assert_response :success
      assert_select 'textarea#content_text' do |elements|
        assert_match /withtemplate/i, elements.first.text.strip
      end
    end
  end

  test "new wiki open with template global" do
    create_wiki_tree(@project)
    page = WikiPage.find_by(title: 'GlobTemplate_1', wiki: @project.wiki)
    workflow = WikiApprovalWorkflow.find_by(page_id: page.id)&.latest_public_version
    get "/projects/#{@project.identifier}/wiki/withtemplate?rwa_template_id=#{workflow.id}", headers: { "HTTP_ACCEPT" => "text/javascript" }

    assert_response :success
    assert_select 'textarea#content_text' do |elements|
      assert_equal 'Test content template GlobTemplate 1', elements.first.text.strip
    end
  end

  test "new wiki open with template global not enabled" do
    create_wiki_tree(@project)
    page = WikiPage.find_by(title: 'GlobTemplate_1', wiki: @project.wiki)
    workflow = WikiApprovalWorkflow.find_by(page_id: page.id)&.latest_public_version
    with_project_wiki_settings(@project,
    { wiki_templates: ['projects'] }
    ) do
      get "/projects/#{@project.identifier}/wiki/withtemplate?rwa_template_id=#{workflow.id}", headers: { "HTTP_ACCEPT" => "text/javascript" }

      assert_response :success
      assert_select 'textarea#content_text' do |elements|
        assert_match /withtemplate/i, elements.first.text.strip
      end
    end
  end

  test "new wiki open with template projects role" do
    create_wiki_tree(@project)
    page = WikiPage.find_by(title: 'Manager_proj', wiki: @project.wiki)
    workflow = WikiApprovalWorkflow.find_by(page_id: page.id)&.latest_public_version
    get "/projects/#{@project.identifier}/wiki/withtemplate?rwa_template_id=#{workflow.id}", headers: { "HTTP_ACCEPT" => "text/javascript" }

    assert_response :success
    assert_select 'textarea#content_text' do |elements|
      assert_equal 'Test content template Manager proj', elements.first.text.strip
    end
  end

  test "new wiki open with template projects role not enabled" do
    create_wiki_tree(@project)
    page = WikiPage.find_by(title: 'Manager_proj', wiki: @project.wiki)
    workflow = WikiApprovalWorkflow.find_by(page_id: page.id)&.latest_public_version
    with_project_wiki_settings(@project,
    { wiki_templates: ['global'] }
    ) do
      get "/projects/#{@project.identifier}/wiki/withtemplate?rwa_template_id=#{workflow.id}", headers: { "HTTP_ACCEPT" => "text/javascript" }

      assert_response :success
      assert_select 'textarea#content_text' do |elements|
        assert_match /withtemplate/i, elements.first.text.strip
      end
    end
  end

  test "new wiki open with template role" do
    create_wiki_tree(@project)
    page = WikiPage.find_by(title: 'Manager_first', wiki: @project.wiki)
    workflow = WikiApprovalWorkflow.find_by(page_id: page.id)&.latest_public_version
    get "/projects/#{@project.identifier}/wiki/withtemplate?rwa_template_id=#{workflow.id}", headers: { "HTTP_ACCEPT" => "text/javascript" }

    assert_response :success
    assert_select 'textarea#content_text' do |elements|
      assert_equal 'Test content template Manager first', elements.first.text.strip
    end
  end

  test "new wiki open with template role not enabled" do
    create_wiki_tree(@project)
    page = WikiPage.find_by(title: 'Manager_first', wiki: @project.wiki)
    workflow = WikiApprovalWorkflow.find_by(page_id: page.id)&.latest_public_version
    with_project_wiki_settings(@project,
    { wiki_templates: ['global'] }
    ) do
      get "/projects/#{@project.identifier}/wiki/withtemplate?rwa_template_id=#{workflow.id}", headers: { "HTTP_ACCEPT" => "text/javascript" }

      assert_response :success
      assert_select 'textarea#content_text' do |elements|
        assert_match /withtemplate/i, elements.first.text.strip
      end
    end
  end

  test "new wiki open with template role not as manager" do
    create_wiki_tree(@project)
    member = Member.find_by(user: @jsmith, project: @project)
    member.roles = [Role.find_by(name: 'Developer')]
    member.save!
    page = WikiPage.find_by(title: 'Manager_first', wiki: @project.wiki)
    workflow = WikiApprovalWorkflow.find_by(page_id: page.id)&.latest_public_version
    get "/projects/#{@project.identifier}/wiki/withtemplate?rwa_template_id=#{workflow.id}", headers: { "HTTP_ACCEPT" => "text/javascript" }

    assert_response :success
    assert_select 'textarea#content_text' do |elements|
      assert_match /withtemplate/i, elements.first.text.strip
    end
  end

  test "new wiki open with template role not enabled only projects" do
    create_wiki_tree(@project)
    page = WikiPage.find_by(title: 'Manager_first', wiki: @project.wiki)
    workflow = WikiApprovalWorkflow.find_by(page_id: page.id)&.latest_public_version
    with_project_wiki_settings(@project,
    { wiki_templates: ['projects'] }
    ) do
      get "/projects/#{@project.identifier}/wiki/withtemplate?rwa_template_id=#{workflow.id}", headers: { "HTTP_ACCEPT" => "text/javascript" }

      assert_response :success
      assert_select 'textarea#content_text' do |elements|
        assert_match /withtemplate/i, elements.first.text.strip
      end
    end
  end

  test "new wiki open with template project role only projects" do
    create_wiki_tree(@project)
    page = WikiPage.find_by(title: 'Manager_proj', wiki: @project.wiki)
    workflow = WikiApprovalWorkflow.find_by(page_id: page.id)&.latest_public_version
    with_project_wiki_settings(@project,
    { wiki_templates: ['projects'] }
    ) do
      get "/projects/#{@project.identifier}/wiki/withtemplate?rwa_template_id=#{workflow.id}", headers: { "HTTP_ACCEPT" => "text/javascript" }

      assert_response :success
      assert_select 'textarea#content_text' do |elements|
        assert_equal 'Test content template Manager proj', elements.first.text.strip
      end
    end
  end
end
