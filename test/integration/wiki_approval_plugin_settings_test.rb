# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class WikiApprovalPluginSettingsTest < WikiApproval::Test::IntegrationCase
  def setup
    log_user('admin', 'admin')
  end

  def test_settings_page_loads
    get '/settings/plugin/redmine_wiki_approval'
    assert_response :success

    # all fields
    assert_select 'select[name="settings[wiki_approval_settings_comment]"]'
    assert_select 'select[name="settings[wiki_approval_settings_draft_enabled]"]'
    assert_select 'select[name="settings[wiki_approval_settings_enabled]"]'
    assert_select 'select[name="settings[wiki_approval_settings_required]"]'
    assert_select 'select[name="settings[wiki_approval_settings_version]"]'
    assert_select 'select[name="settings[wiki_approval_settings_content_draft]"]'

    # all available options (Yes, No, Projects)
    assert_select 'option[value="true"]'
    assert_select 'option[value="false"]'
    assert_select 'option[value="project"]'
  end

  def test_update_all_settings
    post '/settings/plugin/redmine_wiki_approval',
         params: {
           settings: {
             wiki_approval_settings_comment: 'true',
             wiki_approval_settings_draft_enabled: 'false',
             wiki_approval_settings_enabled: 'project',
             wiki_approval_settings_required: 'true',
             wiki_approval_settings_version: 'false',
             wiki_approval_settings_content_draft: 'project'
           }
         }

    assert_redirected_to '/settings/plugin/redmine_wiki_approval'
    follow_redirect!
    assert_response :success

    # check saved values
    assert_equal 'true', Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_comment]
    assert_equal 'false', Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_draft_enabled]
    assert_equal 'project', Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_enabled]
    assert_equal 'true', Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_required]
    assert_equal 'false', Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_version]
    assert_equal 'project', Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_content_draft]
  end

  def test_project_plugin_settings
    get '/projects/1/settings/wiki_approval'
    assert_response :success
  end
end
