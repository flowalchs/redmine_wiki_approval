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
      # approval_required_box checked
      assert_select 'input#approval_required_box[type=checkbox][name=wiki_approval_required][value="1"]', 1
      assert_select 'input#approval_required_box[type=checkbox][checked=checked]', 1
      # Hidden-Fallback
      assert_select 'input#wiki_approval_required[type=hidden][name=wiki_approval_required][value="0"]', 1

      # approval_enabled_box checked
      assert_select 'input#approval_enabled_box[type=checkbox][name=wiki_approval_enabled][value="1"]', 1
      assert_select 'input#approval_enabled_box[type=checkbox][checked=checked]', 1
      # Hidden-Fallback
      assert_select 'input#wiki_approval_enabled[type=hidden][name=wiki_approval_enabled][value="0"]', 1

      # hidden wiki_draft_enabled
      assert_select 'input#wiki_draft_enabled[type=checkbox][name=wiki_draft_enabled]', 0
      # hidden approval_enabled
      assert_select 'input#wiki_comment_required[type=checkbox][name=wiki_comment_required]', 0
      # hidden wiki_content_draft
      assert_select 'input#wiki_content_draft[type=checkbox][name=wiki_content_draft]', 0
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
      # hidden approval_required
      assert_select 'input#approval_required_box[type=checkbox][name=wiki_approval_required][value="1"]', 0
      # hidden approval_enabled
      assert_select 'input#approval_enabled_box[type=checkbox][name=wiki_approval_enabled][value="1"]', 0

      # wiki_draft_enabled checked
      assert_select 'input#wiki_draft_enabled[type=checkbox][checked=checked]', 1
      # Hidden-Fallback
      assert_select 'input#wiki_draft_enabled[type=hidden][name=wiki_draft_enabled][value="0"]', 1

      # wiki_comment_required checked
      assert_select 'input#wiki_comment_required[type=checkbox][checked=checked]', 1
      # Hidden-Fallback
      assert_select 'input#wiki_comment_required[type=hidden][name=wiki_comment_required][value="0"]', 1

      # wiki_content_draft
      assert_select 'input#wiki_content_draft[type=checkbox][checked=checked]', 1
      assert_select 'input#wiki_content_draft[type=hidden][name=wiki_content_draft][value="0"]', 1
    end
  end
end
