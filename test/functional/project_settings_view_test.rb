# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class ProjectSettingsViewTest < WikiApproval::Test::ControllerCase
  tests ProjectsController

  def setup
    super
    set_session_user(@admin)
  end

  test "view additional project settings fields" do
    get :settings, params: { id: @project.identifier, tab: 'wiki_approval' }
    assert_response :success
    # modul enabled
    assert_select 'input#project_enabled_module_names_wiki_approval[type=checkbox][checked=checked]', 1
    # tab selected
    assert_select 'div.tabs ul li a#tab-wiki_approval.selected', 1

    assert_select 'div#tab-content-wiki_approval div#wiki_approval_settings' do
      # wiki_approval_required
      assert_select 'input[type=checkbox][name=wiki_approval_required][value="1"][checked=checked]', 1
      assert_select 'input[type=hidden][name=wiki_approval_required][value="0"]', 1

      # wiki_approval_enabled
      assert_select 'input[type=checkbox][name=wiki_approval_enabled][value="1"][checked=checked]', 1
      assert_select 'input[type=hidden][name=wiki_approval_enabled][value="0"]', 1

      # --- Sidebar Status (multiselect) ---
      assert_select 'select[name="wiki_sidebar_status[]"][multiple]', 0

      # wiki_draft_enabled soll NICHT als checkbox existieren
      assert_select 'input[type=checkbox][name=wiki_draft_enabled]', 0

      # wiki_comment_required soll NICHT als checkbox existieren
      assert_select 'input[type=checkbox][name=wiki_comment_required]', 0

      # wiki_content_draft soll NICHT als checkbox existieren
      assert_select 'input[type=checkbox][name=wiki_content_draft]', 0
    end
  end

  test "view project settings hidden approval hidden approval enabled" do
    # Plugin-Settings to 'project'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_comment] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_draft_enabled] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_enabled] = 'false'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_required] = 'false'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_version] = 'false'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_content_draft] = WikiApprovalSettingsHelper::PROJECT

    get :settings, params: { id: @project.identifier, tab: 'wiki_approval' }
    assert_response :success
    assert_select 'div#tab-content-wiki_approval div#wiki_approval_settings' do
      # approval Felder (sollten nicht existieren)
      assert_select 'input[type=checkbox][name=wiki_approval_required][value="1"]', 0
      assert_select 'input[type=checkbox][name=wiki_approval_enabled][value="1"]', 0

      # wiki_draft_enabled
      assert_select 'input[type=checkbox][name=wiki_draft_enabled][value="1"][checked=checked]', 1
      assert_select 'input[type=hidden][name=wiki_draft_enabled][value="0"]', 1

      # --- Sidebar Status (multiselect) ---
      assert_select 'select[name="wiki_sidebar_status[]"][multiple]', 0

      # wiki_comment_required
      assert_select 'input[type=checkbox][name=wiki_comment_required][value="1"][checked=checked]', 1
      assert_select 'input[type=hidden][name=wiki_comment_required][value="0"]', 1

      # wiki_content_draft
      assert_select 'input[type=checkbox][name=wiki_content_draft][value="1"][checked=checked]', 1
      assert_select 'input[type=hidden][name=wiki_content_draft][value="0"]', 1
    end
  end

  test "view project all settings" do
    # Plugin-Settings to 'project'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_comment] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_draft_enabled] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_enabled] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_required] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_version] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_content_draft] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_sidebar_project] = 1

    get :settings, params: { id: @project.identifier, tab: 'wiki_approval' }
    assert_response :success
    assert_select 'div#tab-content-wiki_approval div#wiki_approval_settings' do
      # --- Settings ---

      # wiki_comment_required
      assert_select 'input[type=checkbox][name=wiki_comment_required][checked]', 1
      assert_select 'input[type=hidden][name=wiki_comment_required][value="0"]', 1

      # wiki_content_draft
      assert_select 'input[type=checkbox][name=wiki_content_draft][checked]', 1
      assert_select 'input[type=hidden][name=wiki_content_draft][value="0"]', 1

      # --- Sidebar Status (multiselect) ---
      assert_select 'select[name="wiki_sidebar_status[]"][multiple]', 1

      # ausgewählte Optionen prüfen
      assert_select 'select[name="wiki_sidebar_status[]"] option[selected][value="canceled"]', 1
      assert_select 'select[name="wiki_sidebar_status[]"] option[selected][value="draft"]', 1
      assert_select 'select[name="wiki_sidebar_status[]"] option[selected][value="published"]', 1
      assert_select 'select[name="wiki_sidebar_status[]"] option[selected][value="pending"]', 1
      assert_select 'select[name="wiki_sidebar_status[]"] option[selected][value="rejected"]', 1
      assert_select 'select[name="wiki_sidebar_status[]"] option[selected][value="released"]', 1

      # wiki_draft_enabled
      assert_select 'input[type=checkbox][name=wiki_draft_enabled][checked]', 1
      assert_select 'input[type=hidden][name=wiki_draft_enabled][value="0"]', 1

      # wiki_approval_enabled
      assert_select 'input[type=checkbox][name=wiki_approval_enabled][checked]', 1
      assert_select 'input[type=hidden][name=wiki_approval_enabled][value="0"]', 1

      # wiki_approval_required
      assert_select 'input[type=checkbox][name=wiki_approval_required][checked]', 1
      assert_select 'input[type=hidden][name=wiki_approval_required][value="0"]', 1

      # wiki_approval_version
      assert_select 'input[type=checkbox][name=wiki_approval_version][checked]', 1
      assert_select 'input[type=hidden][name=wiki_approval_version][value="0"]', 1
    end

    assert RedmineWikiApproval::Settings.draft_create?(@project)
    assert RedmineWikiApproval::Settings.approval_start?(@project)
    assert RedmineWikiApproval::Settings.is_allowed_to_show_last_version?(@project)
    assert RedmineWikiApproval::Settings.approval_enabled?(@project)
    assert RedmineWikiApproval::Settings.approval_publish?(@project)
    assert RedmineWikiApproval::Settings.approval_or_draft_enabled?(@project)
    assert RedmineWikiApproval::Settings.wiki_comment_required?(@project)
    assert RedmineWikiApproval::Settings.view_draft?(@project)
    assert RedmineWikiApproval::Settings.content_draft?(@project)
  end

  test "get project all settings diffent values " do
    # Plugin-Settings to 'project'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_comment] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_draft_enabled] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_enabled] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_required] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_version] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_content_draft] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_sidebar_project] = 1

    # all false
    setting = WikiApprovalSetting.find_by(project_id: @project.id)
    setting.wiki_comment_required = false
    setting.wiki_draft_enabled = false
    setting.wiki_approval_enabled = false
    setting.wiki_approval_required = false
    setting.wiki_approval_version = false
    setting.wiki_content_draft = false
    setting.wiki_sidebar_status = ['']
    setting.save!

    get :settings, params: { id: @project.identifier, tab: 'wiki_approval' }
    assert_response :success

    assert_select 'div#tab-content-wiki_approval div#wiki_approval_settings' do
      # --- Settings ---

      # wiki_comment_required
      assert_select 'input[type=checkbox][name=wiki_comment_required][checked]', 0
      assert_select 'input[type=hidden][name=wiki_comment_required][value="0"]', 1

      # wiki_content_draft
      assert_select 'input[type=checkbox][name=wiki_content_draft][checked]', 0
      assert_select 'input[type=hidden][name=wiki_content_draft][value="0"]', 1

      # --- Sidebar Status (multiselect) ---
      assert_select 'select[name="wiki_sidebar_status[]"][multiple]', 1

      # nicht ausgewählt
      assert_select 'select[name="wiki_sidebar_status[]"] option[value="canceled"]:not([selected])', 1
      assert_select 'select[name="wiki_sidebar_status[]"] option[value="draft"]:not([selected])', 1
      assert_select 'select[name="wiki_sidebar_status[]"] option[value="published"]:not([selected])', 1
      assert_select 'select[name="wiki_sidebar_status[]"] option[value="pending"]:not([selected])', 1
      assert_select 'select[name="wiki_sidebar_status[]"] option[value="rejected"]:not([selected])', 1
      assert_select 'select[name="wiki_sidebar_status[]"] option[value="released"]:not([selected])', 1

      # wiki_draft_enabled
      assert_select 'input[type=checkbox][name=wiki_draft_enabled][checked]', 0
      assert_select 'input[type=hidden][name=wiki_draft_enabled][value="0"]', 1

      # wiki_approval_enabled
      assert_select 'input[type=checkbox][name=wiki_approval_enabled][checked]', 0
      assert_select 'input[type=hidden][name=wiki_approval_enabled][value="0"]', 1

      # wiki_approval_required
      assert_select 'input[type=checkbox][name=wiki_approval_required][checked]', 0
      assert_select 'input[type=hidden][name=wiki_approval_required][value="0"]', 1

      # wiki_approval_version
      assert_select 'input[type=checkbox][name=wiki_approval_version][checked]', 0
      assert_select 'input[type=hidden][name=wiki_approval_version][value="0"]', 1
    end

    assert_not RedmineWikiApproval::Settings.draft_create?(@project)
    assert_not RedmineWikiApproval::Settings.approval_start?(@project)
    assert_not RedmineWikiApproval::Settings.is_allowed_to_show_last_version?(@project)
    assert_not RedmineWikiApproval::Settings.approval_enabled?(@project)
    assert_not RedmineWikiApproval::Settings.approval_publish?(@project)
    assert_not RedmineWikiApproval::Settings.approval_or_draft_enabled?(@project)
    assert_not RedmineWikiApproval::Settings.wiki_comment_required?(@project)
    assert_not RedmineWikiApproval::Settings.view_draft?(@project)
    assert_not RedmineWikiApproval::Settings.content_draft?(@project)
  end

  test "create project with wiki + wiki_approval and open settings tab default values" do
    project = Project.generate!(identifier: 'wiki-approval-test')

    put :update, params: {
      id: project.identifier,
      project: {
        name: project.name,
        identifier: project.identifier,
        enabled_module_names: ['wiki', 'wiki_approval']
      }
    }

    assert_response :redirect
    project.reload
    assert project.module_enabled?('wiki')
    assert project.module_enabled?('wiki_approval')

    get :settings, params: { id: project.identifier, tab: 'wiki_approval' }

    assert_response :success
    assert_select 'div#tab-content-wiki_approval div#wiki_approval_settings' do
      # =========================
      # Approval Workflow
      # =========================

      # wiki_approval_enabled (checked)
      assert_select 'input[type=checkbox][name=wiki_approval_enabled][checked]', 1
      assert_select 'input[type=hidden][name=wiki_approval_enabled][value="0"]', 1

      # wiki_approval_required (checked)
      assert_select 'input[type=checkbox][name=wiki_approval_required][checked]', 1
      assert_select 'input[type=hidden][name=wiki_approval_required][value="0"]', 1

      # =========================
      # NICHT VORHANDENE FELDER
      # =========================

      assert_select 'input[type=checkbox][name=wiki_comment_required]', 0
      assert_select 'input[type=checkbox][name=wiki_content_draft]', 0
      assert_select 'input[type=checkbox][name=wiki_draft_enabled]', 0
      assert_select 'input[type=checkbox][name=wiki_approval_version]', 0

      # optional auch hidden prüfen
      assert_select 'input[type=hidden][name=wiki_comment_required]', 0
      assert_select 'input[type=hidden][name=wiki_content_draft]', 0
      assert_select 'input[type=hidden][name=wiki_draft_enabled]', 0
      assert_select 'input[type=hidden][name=wiki_approval_version]', 0
    end

    assert RedmineWikiApproval::Settings.draft_create?(@project)
    assert RedmineWikiApproval::Settings.approval_start?(@project)
    assert RedmineWikiApproval::Settings.is_allowed_to_show_last_version?(@project)
    assert RedmineWikiApproval::Settings.approval_enabled?(@project)
    assert RedmineWikiApproval::Settings.approval_publish?(@project)
    assert RedmineWikiApproval::Settings.approval_or_draft_enabled?(@project)
    assert_not RedmineWikiApproval::Settings.wiki_comment_required?(@project)
    assert RedmineWikiApproval::Settings.view_draft?(@project)
    assert RedmineWikiApproval::Settings.content_draft?(@project)
  end
end
