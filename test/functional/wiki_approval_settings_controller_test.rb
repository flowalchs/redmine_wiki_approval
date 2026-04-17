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

    post :update, params: {
      project_id: @project.id,
      wiki_comment_required: 'true',
      wiki_draft_enabled: 'false',
      wiki_approval_enabled: 'true',
      wiki_approval_required: 'false',
      wiki_approval_version: 'true',
      wiki_content_draft: 'false'
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

    post :update, params: {
      project_id: @project2.id,
      wiki_comment_required: 'true',
      wiki_draft_enabled: 'false',
      wiki_approval_enabled: 'true',
      wiki_approval_required: 'false',
      wiki_approval_version: 'true',
      wiki_content_draft: 'true'
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
end
