# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class WikiApprovalSettingsControllerTest < WikiApproval::Test::ControllerCase
  tests WikiApprovalSettingsController

  def setup
    super
    set_session_user(@admin)
  end

  test "save additional settings fields" do
    # Plugin-Settings to 'project'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_comment] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_draft_enabled] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_enabled] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_required] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_version] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_content_draft] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_sidebar_project] = 1
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_templates] = RedmineWikiApproval::WikiTemplates::ENABLED_TEMPLATE_TYPES

    post :update, params: {
      project_id: @project.id,
      wiki_comment_required: 'true',
      wiki_draft_enabled: 'false',
      wiki_approval_enabled: 'true',
      wiki_approval_required: 'false',
      wiki_approval_version: 'true',
      wiki_content_draft: 'false',
      wiki_sidebar_status: ["", "draft", "pending"],
      wiki_templates: ["projects"]
    }

    assert_response :redirect
    setting = WikiApprovalSetting.find(@project.id)
    setting.reload

    assert setting.wiki_comment_required
    assert_not setting.wiki_draft_enabled
    assert setting.wiki_approval_enabled
    assert_not setting.wiki_approval_required
    assert setting.wiki_approval_version
    assert_not setting.wiki_content_draft
    assert_equal ["draft", "pending"], setting.wiki_sidebar_status
    assert_equal ["projects"], setting.wiki_templates
  end

  test "save find or create" do
    @project2.enable_module! :wiki_approval

    # Plugin-Settings to 'project'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_comment] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_draft_enabled] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_enabled] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_required] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_version] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_content_draft] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_sidebar_project] = 0
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_templates] = RedmineWikiApproval::WikiTemplates::ENABLED_TEMPLATE_TYPES

    post :update, params: {
      project_id: @project2.id,
      wiki_comment_required: 'true',
      wiki_draft_enabled: 'false',
      wiki_approval_enabled: 'true',
      wiki_approval_required: 'false',
      wiki_approval_version: 'true',
      wiki_content_draft: 'true',
      wiki_sidebar_status: [""]
    }

    assert_response :redirect
    setting = WikiApprovalSetting.find_by(project_id: @project2.id)
    setting.reload

    assert setting.wiki_comment_required
    assert_not setting.wiki_draft_enabled
    assert setting.wiki_approval_enabled
    assert_not setting.wiki_approval_required
    assert setting.wiki_approval_version
    assert setting.wiki_content_draft
    # default value
    assert_equal ["canceled", "draft", "pending", "rejected", "released", "published"], setting.wiki_sidebar_status
    assert_equal [], setting.wiki_templates
  end

  test "data_hash should rescue JSON::ParserError and return empty hash" do
    setting = WikiApprovalSetting.new(project_id: 1)

    # Wir umgehen den Setter und schreiben direkt korrupten Text in die Spalte
    setting.json_data = "{ invalid json: 'missing quotes' "

    # Sicherstellen, dass der Parser-Fehler gefangen wird
    assert_nothing_raised do
      assert_equal({}, setting.data_hash, "Sollte leeren Hash bei ParserError liefern")
    end
  end

  test "data_hash= should set json_data and internal hash" do
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_comment] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_draft_enabled] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_enabled] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_required] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_version] = WikiApprovalSettingsHelper::PROJECT
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_content_draft] = WikiApprovalSettingsHelper::PROJECT

    setting = WikiApprovalSetting.new(project_id: 1)
    test_hash = { wiki_comment_required: 'true', some_custom_key: "value" }

    setting.data_hash = test_hash

    # 1. Prüfe ob json_data (String) korrekt gesetzt wurde
    assert_equal test_hash.to_json, setting.json_data

    # 2. Prüfe ob nach dem Speichern und Neuladen alles passt
    setting.save!
    setting.reload
    assert setting.wiki_comment_required
    assert_equal "value", setting.data_hash[:some_custom_key]
  end

  test "should show flash error and redirect when update fails" do
    # simulation error
    WikiApprovalSetting.any_instance.stubs(:update!).raises(StandardError, "Database Error")

    post :update, params: {
      project_id: @project.id,
      wiki_comment_required: '1'
    }

    assert_not_nil flash[:error]
    assert_equal "Updating failed.Database Error", flash[:error]
    assert_redirected_to :controller => 'projects', :action => 'settings', :id => @project.identifier, :tab => 'wiki_approval'
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

    # PATCH Request (wie im echten Formular)
    post :update, params: {
      project_id: @project.id,
      wiki_comment_required: "0",
      wiki_content_draft: "0",
      wiki_draft_enabled: "0",
      wiki_approval_enabled: "0",
      wiki_approval_required: "0",
      wiki_approval_version: "0",
      wiki_sidebar_status: [""],
      wiki_templates: [""]
    }

    assert_response :redirect
    setting = WikiApprovalSetting.find_by(project_id: @project.id)
    setting.reload

    assert_not setting.wiki_comment_required
    assert_not setting.wiki_draft_enabled
    assert_not setting.wiki_approval_enabled
    assert_not setting.wiki_approval_required
    assert_not setting.wiki_approval_version
    assert_not setting.wiki_content_draft
    assert_equal [], setting.wiki_sidebar_status
    assert_equal [], setting.wiki_templates

    assert_not RedmineWikiApproval::Settings.draft_create?(@project)
    assert_not RedmineWikiApproval::Settings.approval_start?(@project)
    assert_not RedmineWikiApproval::Settings.is_allowed_to_show_last_version?(@project)
    assert_not RedmineWikiApproval::Settings.approval_enabled?(@project)
    assert_not RedmineWikiApproval::Settings.approval_publish?(@project)
    assert_not RedmineWikiApproval::Settings.approval_or_draft_enabled?(@project)
    assert_not RedmineWikiApproval::Settings.wiki_comment_required?(@project)
    assert_not RedmineWikiApproval::Settings.view_draft?(@project)
    assert_not RedmineWikiApproval::Settings.content_draft?(@project)
    assert_not RedmineWikiApproval::Settings.wiki_templates(@project).any?
  end
end
