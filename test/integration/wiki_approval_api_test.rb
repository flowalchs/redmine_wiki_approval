# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class WikiApprovalApiTest < WikiApproval::Test::IntegrationCase
  def setup
    super
    Setting.rest_api_enabled = '1'
    @page = WikiPage.find_by(id: 11)
    @dlopper_header = credentials('dlopper', 'foo')
    @jsmith_header = credentials('jsmith')
    @admin_header = credentials('admin')
  end

  # STATUS
  def test_get_approval_status_via_api
    get "/projects/#{@project.id}/wiki_approval/#{@page.title}/status.json", :headers => @jsmith_header

    assert_response :success

    json = JSON.parse(response.body)
    assert_kind_of Hash, json

    assert json.has_key?('wiki_approval_workflow')

    # Zugriff auf das Root-Element
    workflow = json['wiki_approval_workflow']
    assert_not_nil workflow, "Root-Element 'wiki_approval_workflow' fehlt im JSON"

    # 1. Hauptattribute prüfen
    assert_equal 2, workflow['id']
    assert_equal 'pending', workflow['status']
    assert_equal 'John Smith', workflow['author']['name']

    # 2. Die verschachtelte Wiki-Page prüfen
    page = workflow['wiki_page']
    assert_equal 11, page['id']
    assert_equal 'Page_with_sections', page['title']

    # 3. Das Array der Workflow-Steps prüfen
    steps = workflow['wiki_approval_workflow_steps']
    assert_equal 1, steps.size

    step = steps.first
    assert_equal 1, step['step']
    assert_equal 'Dave Lopper', step['principal']['name']
    assert_equal 'User', step['principal']['type']
  end

  def test_unauthorized_status_api_call
    get "/projects/#{@project.id}/wiki_approval/#{@page.title}/status.json"
    assert_response :unauthorized
  end

  def test_page_not_found_status_api_call
    get "/projects/#{@project.id}/wiki_approval/notFound/status.json", :headers => @jsmith_header
    assert_response :not_found
  end

  # START
  def test_start_approval_process_success
    put(
      "/projects/#{@project.id}/wiki_approval/#{@page.title}/start.json",
      :params => {
        :note => "Initialer Start über API",
        :steps => [
          { step: 1, step_type: "or", principal_id: 3 }, # Dave Lopper
          { step: 1, step_type: "or", principal_id: 1 }  # Admin
        ]
      },
      :headers => @jsmith_header
    )

    # 1. Response Status prüfen
    assert_response :success

    # 2. JSON Struktur validieren
    json = JSON.parse(response.body)
    workflow = json['wiki_approval_workflow']

    assert_equal 'pending', workflow['status']
    assert_equal 'Initialer Start über API', workflow['note']

    # 3. Prüfen, ob die Schritte korrekt angelegt wurden
    steps = workflow['wiki_approval_workflow_steps']
    assert_equal 2, steps.size
    assert_equal 1, steps.first['step']
    assert_equal 'or', steps.first['step_type']

    # 4. Datenbank-Check: Wurde wirklich ein Datensatz erstellt?
    # Hier den Namen deines Models einsetzen, z.B. WikiApprovalWorkflow
    last_workflow = WikiApprovalWorkflow.last
    assert_equal 'pending', last_workflow.status
    assert_equal 2, last_workflow.approval_steps.count
  end

  def test_start_approval_duplicat_user
    put(
      "/projects/#{@project.id}/wiki_approval/#{@page.title}/start.json",
      :params => {
        :note => "duplicat_user",
        :steps => [
          { step: 1, step_type: "or", principal_id: 3 }, # Dave Lopper
          { step: 1, step_type: "or", principal_id: 3 }  # Dave Lopper double
        ]
      },
      :headers => @jsmith_header
    )

    assert_response :unprocessable_entity
  end

  def test_start_approval_without_permission
    assert @manager_role.has_permission?(:wiki_approval_start)
    @manager_role.permissions.delete(:wiki_approval_start)
    @manager_role.save!

    assert @developer_role.has_permission?(:wiki_approval_start)
    @developer_role.permissions.delete(:wiki_approval_start)
    @developer_role.save!

    put(
      "/projects/#{@project.id}/wiki_approval/#{@page.title}/start.json",
      :params => {
        :note => "only one user",
        :steps => [
          { step: 1, step_type: "or", principal_id: 3 }, # Dave Lopper
          { step: 1, step_type: "or", principal_id: 1 }  # admin
        ]
      },
      :headers => @jsmith_header
    )

    assert_response :forbidden
  end

  def test_start_approval_not_enabled
    current_settings = Setting.plugin_redmine_wiki_approval.symbolize_keys
    updates = {
      wiki_approval_settings_enabled: "false",
      wiki_approval_settings_required: "false",
      wiki_approval_settings_version: "false"
    }
    Setting.plugin_redmine_wiki_approval = current_settings.merge(updates)
    Setting.clear_cache

    put(
      "/projects/#{@project.id}/wiki_approval/#{@page.title}/start.json",
      :params => {
        :note => "Initialer Start über API",
        :steps => [
          { step: 1, step_type: "or", principal_id: 3 }, # Dave Lopper
          { step: 1, step_type: "or", principal_id: 1 }  # Admin
        ]
      },
      :headers => @jsmith_header
    )

    assert_response :forbidden
  end

  def test_start_approval_version_was_released
    # delete version 3 from page
    version_to_delete = @page.content.versions.find_by(version: 3)
    version_to_delete.destroy
    @page.reload

    put(
      "/projects/#{@project.id}/wiki_approval/#{@page.title}/start.json",
      :params => {
        :note => "duplicat_user",
        :steps => [
          { step: 1, step_type: "or", principal_id: 3 }, # Dave Lopper
          { step: 1, step_type: "or", principal_id: 1 }  # Dave Lopper double
        ]
      },
      :headers => @jsmith_header
    )
    assert_response :unprocessable_entity
  end

  # GRANT
  def test_grant_approval_no_step_found_for_user
    put "/projects/#{@project.id}/wiki_approval/#{@page.title}/grant.json", :headers => @jsmith_header
    assert_response :not_found
  end

  def test_grant_approval
    assert_equal 'pending', @page.current_wiki_aw.status

    put "/projects/#{@project.id}/wiki_approval/#{@page.title}/grant.json", :headers => @dlopper_header
    assert_response :success

    # 2. JSON Struktur validieren
    json = JSON.parse(response.body)
    workflow = json['wiki_approval_workflow']

    assert_equal 'released', workflow['status']
    steps = workflow['wiki_approval_workflow_steps']
    assert_equal 1, steps.size

    @page.reload
    assert_equal 'released', @page.current_wiki_aw.status
  end

  def test_grant_approval_rejected
    put "/projects/#{@project.id}/wiki_approval/#{@page.title}/grant.json?step_status=rejected&note=new note", :headers => @dlopper_header
    assert_response :success

    # 2. JSON Struktur validieren
    json = JSON.parse(response.body)
    workflow = json['wiki_approval_workflow']

    assert_equal 'rejected', workflow['status']
    @page.reload
    assert_equal 'rejected', @page.current_wiki_aw.status
  end

  def test_grant_approval_unprocess_status
    put "/projects/#{@project.id}/wiki_approval/#{@page.title}/grant.json?step_status=released", :headers => @dlopper_header
    assert_response :unprocessable_entity
  end

  def test_grant_approval_reject_note
    put "/projects/#{@project.id}/wiki_approval/#{@page.title}/grant.json?step_status=rejected", :headers => @dlopper_header
    assert_response :unprocessable_entity
  end

  # FORWARD
  def test_forward_approval
    put "/projects/#{@project.id}/wiki_approval/#{@page.title}/forward.json?principal_id=5&note=new note", :headers => @dlopper_header
    assert_response :success

    json = JSON.parse(response.body)
    json = json['wiki_approval_workflow']

    # 1. Hauptattribute des Workflows
    assert_equal 2, json['id']
    assert_equal 'pending', json['status']
    assert_equal 'in pending', json['note']
    assert_equal 2, json['author']['id']
    assert_equal 'John Smith', json['author']['name']

    # 2. Den spezifischen Schritt prüfen (Array-Check)
    steps = json['wiki_approval_workflow_steps']
    assert_equal 1, steps.size

    step = steps.first
    assert_equal 1, step['step']
    assert_equal 'or', step['step_type']
    assert_equal 'pending', step['step_status']
    assert_equal 'new note', step['note']

    # Principal (der Prüfer) im Schritt
    assert_equal 5, step['principal']['id']
    assert_equal 'Dave2 Lopper2', step['principal']['name']
  end

  def test_forward_approval_without_note
    put "/projects/#{@project.id}/wiki_approval/#{@page.title}/forward.json?principal_id=5", :headers => @dlopper_header
    assert_response :unprocessable_entity
  end

  def test_forward_approval_to_author
    put "/projects/#{@project.id}/wiki_approval/#{@page.title}/forward.json?principal_id=1&note=new note", :headers => @dlopper_header
    assert_response :not_found
  end

  def test_forward_approval_to_same_user
    put "/projects/#{@project.id}/wiki_approval/#{@page.title}/forward.json?principal_id=3&note=new note", :headers => @dlopper_header
    assert_response :unprocessable_entity
  end

  def test_forward_approval_get_not_found
    get "/projects/#{@project.id}/wiki_approval/#{@page.title}/forward.json?principal_id=5&note=new note", :headers => @dlopper_header
    assert_response :not_found
  end

  # HISTORY
  def test_history_approval
    get "/projects/#{@project.id}/wiki_approval/#{@page.title}/history.json", :headers => @dlopper_header
    assert_response :success

    json = JSON.parse(response.body)

    assert_equal 2, json['total_count']
    assert_equal 0, json['offset']

    json_array = json['wiki_approval_workflows']

    assert_kind_of Array, json_array
    assert_equal 2, json_array.size

    # --- Prüfung des ersten Objekts (ID 2, Status pending) ---
    first = json_array.find { |w| w['id'] == 2 }
    assert_not_nil first
    assert_equal 'pending', first['status']
    assert_equal 'Dave Lopper', first['wiki_approval_workflow_steps'].first['principal']['name']
    assert_nil first['revision'] # Wichtig: Hier ist revision nil

    # --- Prüfung des zweiten Objekts (ID 1, Status released) ---
    second = json_array.find { |w| w['id'] == 1 }
    assert_not_nil second
    assert_equal 'released', second['status']
    assert_equal 1, second['revision']
    assert_equal 'Redmine Admin', second['wiki_approval_workflow_steps'].first['principal']['name']
    assert_equal 'approved', second['wiki_approval_workflow_steps'].first['step_status']

    # 2. Kurzer Check auf den gemeinsamen Autor
    json_array.each do |workflow|
      assert_equal 'John Smith', workflow['author']['name']
    end
  end

  def test_history_approval_page
    30.times do |i|
      WikiApprovalWorkflow.create!(
        page_id: @page.id,
        author_id: 2,
        version: i + 4,
        status: 'published',
        note: "Workflow Nummer #{i}"
      )
    end

    get "/projects/#{@project.id}/wiki_approval/#{@page.title}/history.json?per_page=25&page=2", :headers => @dlopper_header
    assert_response :success

    json = JSON.parse(response.body)

    workflows = json['wiki_approval_workflows']
    assert_kind_of Array, workflows
    assert_equal 7, workflows.size

    # 1. Suche über die Note (ehemals ID 7 Logik)
    latest = workflows.find { |w| w['note'] == 'Workflow Nummer 4' }
    assert_not_nil latest, "Workflow mit Note 'Workflow Nummer 4' nicht gefunden"
    assert_equal 'published', latest['status']
    assert_equal 8, latest['version']
    assert_equal 6, latest['revision']
    assert_empty latest['wiki_approval_workflow_steps']

    # 2. Suche über die Note für den abgebrochenen Workflow (ehemals ID 2)
    # Basierend auf deinem JSON-Beispiel ist die Note hier "in pending"
    canceled_wf = workflows.find { |w| w['note'] == 'in pending' }
    assert_not_nil canceled_wf, "Workflow mit Note 'in pending' nicht gefunden"
    assert_equal 'canceled', canceled_wf['status']

    # Sicherstellen, dass Schritte vorhanden sind, bevor wir darauf zugreifen (Ruby 3.2 Safe)
    steps = canceled_wf['wiki_approval_workflow_steps']
    assert_not_empty steps
    assert_equal 'canceled', steps.first['step_status']
    assert_equal 'Dave Lopper', steps.first['principal']['name']

    # 3. Beispiel für den "released" Workflow (ID 1)
    released_wf = workflows.find { |w| w['note'] == 'is released' }
    assert_not_nil released_wf
    assert_equal 'released', released_wf['status']
    assert_equal 'Redmine Admin', released_wf.dig('wiki_approval_workflow_steps', 0, 'principal', 'name')
  end

  # publish
  def test_publish_approval
    current_settings = Setting.plugin_redmine_wiki_approval.symbolize_keys
    updates = {
      wiki_approval_settings_required: "false",
      wiki_approval_settings_version: "false"
    }
    Setting.plugin_redmine_wiki_approval = current_settings.merge(updates)
    Setting.clear_cache

    put "/projects/#{@project.id}/wiki_approval/#{@page.title}/publish.json", :headers => @dlopper_header
    assert_response :success

    @page.reload
    assert_equal 'published', @page.current_wiki_aw.status
  end

  def test_publish_approval_required
    put "/projects/#{@project.id}/wiki_approval/#{@page.title}/publish.json", :headers => @dlopper_header
    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_equal(["Approval Required"], json_response["errors"])
  end

  def test_publish_approval_released
    current_settings = Setting.plugin_redmine_wiki_approval.symbolize_keys
    updates = {
      wiki_approval_settings_required: "false",
      wiki_approval_settings_version: "false"
    }
    Setting.plugin_redmine_wiki_approval = current_settings.merge(updates)
    Setting.clear_cache

    # delete version 3 from page
    version_to_delete = @page.content.versions.find_by(version: 3)
    version_to_delete.destroy
    @page.reload

    put "/projects/#{@project.id}/wiki_approval/#{@page.title}/publish.json", :headers => @dlopper_header
    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_equal(["Already Released"], json_response["errors"])
  end

  # permissions
  def test_permissions_approval
    get "/projects/#{@project.id}/wiki_approval/permissions.json", :headers => @dlopper_header
    assert_response :success

    json = JSON.parse(response.body)

    # 1. Basis-Check: Existiert das Array und hat es die richtige Größe?
    assert_kind_of Array, json['actors']
    assert_equal 3, json['actors'].size

    # 2. Gezielte Abfrage eines bestimmten Users (z.B. Dave Lopper, ID 3)
    dave = json['actors'].find { |a| a['id'] == 3 }

    assert_not_nil dave, "Dave Lopper (ID 3) wurde im JSON nicht gefunden"
    assert_equal "Dave Lopper", dave['name']
    assert_equal "User", dave['type']

    # 3. Berechtigungen prüfen
    # Prüfen, ob eine spezifische Berechtigung vorhanden ist
    assert_includes dave['permissions'], "wiki_approval_grant"
    assert_includes dave['permissions'], "wiki_approval_publish"

    # 4. Optional: Sicherstellen, dass alle Actors die Mindestberechtigung haben
    json['actors'].each do |actor|
      assert actor['permissions'].include?("wiki_draft_view"),
            "Actor #{actor['name']} fehlt die wiki_draft_view Berechtigung"
    end
  end

  def test_permissions_approval_less_permissions
    @developer_role.permissions.delete(:wiki_approval_start)
    @developer_role.permissions.delete(:wiki_approval_grant)
    @developer_role.save!

    get "/projects/#{@project.id}/wiki_approval/permissions.json", :headers => @dlopper_header
    assert_response :success

    json = JSON.parse(response.body)
    actors = json['actors']

    # 1. John Smith (ID 2) prüfen - Er hat vollen Zugriff inklusive 'grant'
    john = actors.find { |a| a['id'] == 2 }
    assert_not_nil john
    assert_includes john['permissions'], "wiki_approval_grant"
    assert_includes john['permissions'], "wiki_approval_start"

    # 2. Dave Lopper (ID 3) prüfen - Er hat laut deinem JSON KEIN 'grant' und KEIN 'start'
    dave = actors.find { |a| a['id'] == 3 }
    assert_not_nil dave
    assert_includes dave['permissions'], "wiki_approval_forward"
    assert_includes dave['permissions'], "wiki_approval_publish"

    # Negativ-Check: Sicherstellen, dass er wirklich kein 'grant' Recht hat
    assert_not_includes dave['permissions'], "wiki_approval_grant"
    assert_not_includes dave['permissions'], "wiki_approval_start"

    # 3. Struktur-Stichprobe für Dave2
    dave2 = actors.find { |a| a['id'] == 5 }
    assert_equal "Dave2 Lopper2", dave2['name']
    assert_equal "User", dave2['type']
  end

  def test_permissions_approval_filter
    @developer_role.permissions.delete(:wiki_approval_start)
    @developer_role.permissions.delete(:wiki_approval_grant)
    @developer_role.save!

    get "/projects/#{@project.id}/wiki_approval/permissions.json?permissions%5B%5D=wiki_approval_start&permissions%5B%5D=wiki_approval_grant", :headers => @dlopper_header
    assert_response :success

    json = JSON.parse(response.body)
    actors = json['actors']

    # darf nur John Smith im Array sein.
    assert_equal 1, actors.size, "Es sollte nur 1 Actor zurückgegeben werden"

    john = actors.first
    assert_equal 2, john['id']
    assert_equal "John Smith", john['name']

    # 2. Exaktheit der Permissions im JSON prüfen
    expected_permissions = ["wiki_approval_start", "wiki_approval_grant"]
    assert_equal expected_permissions.sort, john['permissions'].sort
    assert_not_includes john['permissions'], "wiki_approval_settings"
  end

  # Wiki Controller update, draft
  def test_update_wiki_content_draft_approval
    assert_difference 'WikiApprovalWorkflow.count', 1 do
      put(
        "/projects/#{@project.id}/wiki/#{@page.title}.json",
        :params => {
          wiki_page: {
            text: "New content…8899",
            comments: "New version"
          },
          status: "draft"
        },
        :headers => @jsmith_header
      )
    end
    assert_response :success

    @page.reload
    assert_equal 'draft', @page.current_wiki_aw.status
  end

  # Wiki Controller update, draft
  def test_update_wiki_content_draft_comment_required
    current_settings = Setting.plugin_redmine_wiki_approval.symbolize_keys
    updates = {
      wiki_approval_settings_comment: "true"
    }
    Setting.plugin_redmine_wiki_approval = current_settings.merge(updates)
    Setting.clear_cache

    assert_difference 'WikiApprovalWorkflow.count', 0 do
      put(
        "/projects/#{@project.id}/wiki/#{@page.title}.json",
        :params => {
          wiki_page: {
            text: "New content…8899",
            comments: ""
          },
          status: "draft"
        },
        :headers => @jsmith_header
      )
    end
    assert_response :unprocessable_entity
  end

  def test_update_wiki_content_published_approval_required
    assert_difference 'WikiApprovalWorkflow.count', 0 do
      put(
        "/projects/#{@project.id}/wiki/#{@page.title}.json",
        :params => {
          wiki_page: {
            text: "New content…8899",
            comments: "New version"
          },
          status: "published"
        },
        :headers => @jsmith_header
      )
    end
    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_equal(["Approval Required"], json_response["errors"])
  end

  def test_update_wiki_content_published_approval
    current_settings = Setting.plugin_redmine_wiki_approval.symbolize_keys
    updates = {
      wiki_approval_settings_required: "false",
      wiki_approval_settings_version: "false"
    }
    Setting.plugin_redmine_wiki_approval = current_settings.merge(updates)
    Setting.clear_cache

    assert_difference 'WikiApprovalWorkflow.count', 1 do
      put(
        "/projects/#{@project.id}/wiki/#{@page.title}.json",
        :params => {
          wiki_page: {
            text: "New content…8899",
            comments: "New version"
          },
          status: "published"
        },
        :headers => @jsmith_header
      )
    end
    assert_response :success
  end

  def test_update_wiki_content_published_permission_denied
    current_settings = Setting.plugin_redmine_wiki_approval.symbolize_keys
    updates = {
      wiki_approval_settings_required: "false",
      wiki_approval_settings_version: "false"
    }
    Setting.plugin_redmine_wiki_approval = current_settings.merge(updates)
    Setting.clear_cache

    @manager_role.remove_permission!(:wiki_approval_publish)
    @developer_role.remove_permission!(:wiki_approval_publish)

    assert_difference 'WikiApprovalWorkflow.count', 0 do
      put(
        "/projects/#{@project.id}/wiki/#{@page.title}.json",
        :params => {
          wiki_page: {
            text: "New content…8899",
            comments: "New version"
          },
          status: "published"
        },
        :headers => @jsmith_header
      )
    end
    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_equal(["Permission denied"], json_response["errors"])
  end

  def test_update_wiki_content_status_not_available
    assert_difference 'WikiApprovalWorkflow.count', 0 do
      put(
        "/projects/#{@project.id}/wiki/#{@page.title}.json",
        :params => {
          wiki_page: {
            text: "New content…8899",
            comments: "New version"
          },
          status: "not available"
        },
        :headers => @jsmith_header
      )
    end
    assert_response :unprocessable_entity
  end

  def test_update_wiki_content_already_released
    current_settings = Setting.plugin_redmine_wiki_approval.symbolize_keys
    updates = {
      wiki_approval_settings_required: "false",
      wiki_approval_settings_version: "false"
    }
    Setting.plugin_redmine_wiki_approval = current_settings.merge(updates)
    Setting.clear_cache

    # delete version 3 from page
    version_to_delete = @page.content.versions.find_by(version: 3)
    version_to_delete.destroy
    @page.reload

    assert_equal 11, @page.current_wiki_aw.current_page_id
    assert_equal 2, @page.current_wiki_aw.version
    assert_equal 'released', @page.current_wiki_aw.status

    # same content.text then its not a new version
    assert_difference 'WikiApprovalWorkflow.count', 0 do
      put(
        "/projects/#{@project.id}/wiki/#{@page.title}.json",
        :params => {
          wiki_page: {
            text: @page.content.text
          },
          status: "published"
        },
        :headers => @jsmith_header
      )
    end
    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_equal(["Already Released"], json_response["errors"])
  end

  # Wiki List index
  def test_get_index
    get "/wiki_approval.json", :headers => @jsmith_header
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal 12, json['total_count']
    assert_equal 0, json['offset']

    pages = json['wiki_pages']
    assert_equal 12, pages.size

    # 2. Eine Seite OHNE Workflow prüfen (z.B. Another_page)
    another_page = pages.find { |p| p['title'] == "Another_page" }
    assert_equal ({}), another_page['wiki_approval_workflow']
    assert_equal "ecookbook", another_page['project']['identifier']

    # 3. Die Seite MIT aktivem Workflow prüfen (Page_with_sections)
    page_with_wf = pages.find { |p| p['title'] == "Page_with_sections" }
    assert_not_nil page_with_wf

    workflow = page_with_wf['wiki_approval_workflow']
    assert_equal 2, workflow['id']
    assert_equal "pending", workflow['status']
    assert_equal "John Smith", workflow['author']['name']

    # 4. Den Workflow-Schritt (Step) tiefenprüfen
    step = workflow['wiki_approval_workflow_steps'].first
    assert_equal "Dave Lopper", step['principal']['name']
    assert_equal "pending", step['step_status']
  end

  def test_get_index_step_me
    get "/wiki_approval.json?step_status=pending&principal_id=me", :headers => @dlopper_header
    assert_response :success

    json = JSON.parse(response.body)
    # 1. Metadaten-Check
    assert_equal 1, json['total_count']
    assert_equal 1, json['wiki_pages'].size

    # 2. Punktuelle Prüfung der Wiki-Seite
    page = json['wiki_pages'].first
    assert_equal 11, page['id']
    assert_equal "Page_with_sections", page['title']
    assert_equal "ecookbook", page['project']['identifier']

    # 3. Tiefenprüfung des Workflows
    workflow = page['wiki_approval_workflow']
    assert_not_nil workflow
    assert_equal "pending", workflow['status']
    assert_equal "John Smith", workflow['author']['name']

    # 4. Prüfung der Workflow-Schritte (Steps)
    steps = workflow['wiki_approval_workflow_steps']
    assert_equal 1, steps.size

    step = steps.first
    assert_equal "pending", step['step_status']
    assert_equal "Dave Lopper", step['principal']['name']
    assert_equal 3, step['principal']['id']
  end

  def test_get_index_step_me_notfound
    get "/wiki_approval.json?step_status=pending&principal_id=me", :headers => @jsmith_header
    assert_response :success

    json = JSON.parse(response.body)
    # 1. Metadaten-Check
    assert_equal 0, json['total_count']
    assert_equal 0, json['wiki_pages'].size
  end

  def test_get_index_my_drafts
    get "/wiki_approval.json", :params => { status: "draft|pending", author_id: "me" }, :headers => @jsmith_header
    assert_response :success

    json = JSON.parse(response.body)
    # 1. Metadaten-Check
    assert_equal 1, json['total_count']
    assert_equal 1, json['wiki_pages'].size

    # 2. Punktuelle Prüfung der Wiki-Seite
    page = json['wiki_pages'].first
    assert_equal 11, page['id']
    assert_equal "Page_with_sections", page['title']
    assert_equal "ecookbook", page['project']['identifier']

    # 3. Tiefenprüfung des Workflows
    workflow = page['wiki_approval_workflow']
    assert_not_nil workflow
    assert_equal "pending", workflow['status']
    assert_equal "John Smith", workflow['author']['name']
  end

  def test_get_index_my_drafts_notfound
    get "/wiki_approval.json?", :params => { status: "draft|pending", author_id: "me" }, :headers => @dlopper_header
    assert_response :success

    json = JSON.parse(response.body)
    # 1. Metadaten-Check
    assert_equal 0, json['total_count']
    assert_equal 0, json['wiki_pages'].size
  end

  def test_get_index_my_drafts_onlydraft_notfound
    get "/wiki_approval.json?status=draft&author_id=me", :headers => @jsmith_header
    assert_response :success

    json = JSON.parse(response.body)
    # 1. Metadaten-Check
    assert_equal 0, json['total_count']
    assert_equal 0, json['wiki_pages'].size
  end

  def test_get_index_drafts_otherusers
    get "/wiki_approval.json", :params => { status: "draft|pending", author_id: "2|4" }, :headers => @dlopper_header
    assert_response :success

    json = JSON.parse(response.body)
    # 1. Metadaten-Check
    assert_equal 1, json['total_count']
    assert_equal 1, json['wiki_pages'].size
  end

  def test_get_index_step_otherusers
    get "/wiki_approval.json", :params => { step_status: "pending", principal_id: "3|4" }, :headers => @jsmith_header
    assert_response :success

    json = JSON.parse(response.body)
    # 1. Metadaten-Check
    assert_equal 1, json['total_count']
    assert_equal 1, json['wiki_pages'].size
  end

  def test_get_index_title
    get "/wiki_approval.json?title=Page_with_sections", :headers => @jsmith_header
    assert_response :success

    json = JSON.parse(response.body)
    # 1. Metadaten-Check
    assert_equal 1, json['total_count']
    assert_equal 1, json['wiki_pages'].size
  end

  def test_get_index_principal_group
    Member.create!(
      project: @project,
      principal: @group,
      roles: [@developer_role]
    )

    step = @page.current_wiki_aw.approval_steps.first
    step.principal = @group
    step.save!

    get "/wiki_approval.json?principal_id=#{@group.id}", :headers => @jsmith_header
    assert_response :success

    json = JSON.parse(response.body)
    # 1. Metadaten-Check
    assert_equal 1, json['total_count']
    assert_equal 1, json['wiki_pages'].size
  end

  def test_get_index_principal_group_user
    Member.create!(
      project: @project,
      principal: @group,
      roles: [@developer_role]
    )

    step = @page.current_wiki_aw.approval_steps.first
    step.principal = @group
    step.save!

    get "/wiki_approval.json?principal_id=#{@group.users.first&.id}", :headers => @jsmith_header
    assert_response :success

    json = JSON.parse(response.body)
    # 1. Metadaten-Check
    assert_equal 1, json['total_count']
    assert_equal 1, json['wiki_pages'].size
  end

  def test_get_index_principal_group_notfound
    get "/wiki_approval.json?principal_id=#{@group.id}", :headers => @jsmith_header
    assert_response :success

    json = JSON.parse(response.body)
    # 1. Metadaten-Check
    assert_equal 0, json['total_count']
    assert_equal 0, json['wiki_pages'].size
  end

  def test_get_index_project
    subproject = @project3
    # Ensure subproject has a wiki
    subproject.create_wiki(start_page: 'Wiki')
    # Add a wiki page to the subproject and update its content
    @page = WikiPage.create!(wiki: subproject.wiki, title: 'Subproject_Page_test')
    WikiContent.create!(page: @page, text: 'content', author_id: 1, updated_on: Time.now)

    get "/projects/#{@project.id}/wiki_approval.json", :headers => @admin_header
    assert_response :success

    json = JSON.parse(response.body)
    pages = json['wiki_pages']

    # 1. Globale Metadaten prüfen
    assert_equal 9, json['total_count']
    assert_equal 9, pages.size

    # 2. Gezielte Prüfung: Seite MIT aktivem Workflow (Page_with_sections)
    page_with_wf = pages.find { |p| p['id'] == 11 }
    assert_not_nil page_with_wf
    assert_equal "Page_with_sections", page_with_wf['title']

    # Workflow-Details
    wf = page_with_wf['wiki_approval_workflow']
    assert_equal "pending", wf['status']
    assert_equal "John Smith", wf['author']['name']
    assert_equal 3, wf['version']

    # Workflow-Steps (Die Genehmiger)
    step = wf['wiki_approval_workflow_steps'].first
    assert_equal "Dave Lopper", step['principal']['name']
    assert_equal "pending", step['step_status']
    assert_equal "or", step['step_type']

    # 3. Gezielte Prüfung: Seite OHNE Workflow (Another_page)
    page_no_wf = pages.find { |p| p['id'] == 2 }
    assert_equal ({}), page_no_wf['wiki_approval_workflow'], "Workflow sollte ein leeres Objekt sein"

    page = pages.find { |p| p['title'] == "Subproject_Page_test" }
    assert_not_nil page, "Subproject_Page_test should be found"
    assert_equal "subproject1", page['project']['identifier']
  end

  def test_get_index_project_patch_subproject
    subproject = @project3
    # Ensure subproject has a wiki
    subproject.create_wiki(start_page: 'Wiki')
    # Add a wiki page to the subproject and update its content
    @page = WikiPage.create!(wiki: subproject.wiki, title: 'Subproject_Page_test')
    WikiContent.create!(page: @page, text: 'content', author_id: 1, updated_on: Time.now)

    post "/projects/#{@project.id}/wiki_approval.json",
      :params => {
        set_filter: 1,
        f: ["subproject_id"],
        op: {
          subproject_id: "!*"
        },
        v: { }
      },
      :headers => @admin_header

    assert_response :success

    json = JSON.parse(response.body)
    pages = json['wiki_pages']

    # 1. Globale Metadaten prüfen
    assert_equal 8, json['total_count']
    assert_equal 8, pages.size

    titles = pages.map { |p| p['title'] }
    assert_not_includes titles, "Subproject_Page_test"
  end

  def test_get_index_project_page
    50.times do |i|
      @page = WikiPage.create!(wiki: @project.wiki, title: "New Test Page #{i}")
      WikiContent.create!(page: @page, text: 'content', author_id: 1, updated_on: Time.now)
    end

    post "/projects/#{@project.id}/wiki_approval.json",
      :params => {
        page: 2,
        per_page: 25
      },
      :headers => @admin_header

    assert_response :success

    json = JSON.parse(response.body)
    pages = json['wiki_pages']

    # 1. Globale Metadaten prüfen
    assert_equal 58, json['total_count']
    assert_equal 25, pages.size
  end

  def test_get_index_project_filter_notme_status
    10.times do |i|
      @page = WikiPage.create!(wiki: @project.wiki, title: "Test Draft Page #{i}")
      content = WikiContent.create!(page: @page, text: 'content', author_id: 1, updated_on: Time.now)
      WikiApprovalWorkflow.create!(
        page_id: @page.id,
        version: content.version,
        status: :draft,
        author_id: @admin.id
      )
    end
    10.times do |i|
      @page = WikiPage.create!(wiki: @project.wiki, title: "Test Published Page #{i}")
      content = WikiContent.create!(page: @page, text: 'content', author_id: 1, updated_on: Time.now)
      WikiApprovalWorkflow.create!(
        page_id: @page.id,
        version: content.version,
        status: :published,
        author_id: @jsmith.id
      )
    end

    post "/projects/#{@project.id}/wiki_approval.json",
      :params => {
        set_filter: 1,
        f: [
          "status"
        ],
        op: {
          status: "="
        },
        v: {
          status: [
            "draft",
            "pending"
          ]
        }
      },
      :headers => @jsmith_header

    assert_response :success
    json = JSON.parse(response.body)
    pages = json['wiki_pages']

    # 1. Gesamtzahl prüfen
    assert_equal 11, json['total_count']
    assert_equal 11, pages.size

    # 2. Status-Validierung (Darf NUR draft oder pending sein)
    allowed_statuses = ['draft', 'pending']

    pages.each do |page|
      status = page.dig('wiki_approval_workflow', 'status')
      assert_includes allowed_statuses, status, "Seite #{page['id']} hat unerlaubten Status: #{status}"
    end

    # 3. Spezifische Zählung (Optional)
    statuses = pages.map { |p| p.dig('wiki_approval_workflow', 'status') }
    assert_equal 10, statuses.count('draft')
    assert_equal 1, statuses.count('pending')

    post "/projects/#{@project.id}/wiki_approval.json",
      :params => {
        set_filter: 1,
        f: [
          "status",
          "author_id"
        ],
        op: {
          status: "=",
          author_id: "!"
        },
        v: {
          status: [
            "draft",
            "pending"
          ],
          author_id: [
            "me"
          ],
        }
      },
      :headers => @jsmith_header

    assert_response :success
    json = JSON.parse(response.body)
    pages = json['wiki_pages']

    # 1. Gesamtzahl prüfen
    assert_equal 10, json['total_count']
    assert_equal 10, pages.size

    post "/projects/#{@project.id}/wiki_approval.json",
      :params => {
        set_filter: 1,
        f: [
          "status",
          "title"
        ],
        op: {
          status: "=",
          title: "~"
        },
        v: {
          status: [
            "draft",
            "pending"
          ],
          title: [
            "Page_with"
          ]
        }
      },
      :headers => @jsmith_header

    assert_response :success
    json = JSON.parse(response.body)
    pages = json['wiki_pages']

    # 1. Gesamtzahl prüfen
    assert_equal 1, json['total_count']
    assert_equal 1, pages.size
    page_with_found_title = pages.find { |p| p['title'] == "Page_with_sections" }
    assert_not_nil page_with_found_title
  end
end
