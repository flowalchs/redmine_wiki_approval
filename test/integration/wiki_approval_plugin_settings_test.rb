# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class WikiApprovalPluginSettingsTest < WikiApproval::Test::IntegrationCase
  def setup
    log_user('admin', 'admin')
  end

  def test_settings_page_loads
    get '/settings/plugin/redmine_wiki_approval'
    assert_response :success

    assert_select 'div#settings.plugin-redmine_wiki_approval' do
      # wiki_comment_required = false
      assert_select 'select[name="settings[wiki_approval_settings_comment]"]' do
        assert_select 'option[value="false"][selected]', 1
      end

      # wiki_content_draft = true
      assert_select 'select[name="settings[wiki_approval_settings_content_draft]"]' do
        assert_select 'option[value="true"][selected]', 1
      end

      # sidebar project checkbox (NOT checked)
      assert_select 'input[type=checkbox][name="settings[wiki_approval_settings_sidebar_project]"]', 1
      assert_select 'input[type=checkbox][name="settings[wiki_approval_settings_sidebar_project]"][checked]', 0

      # hidden fallback vorhanden
      assert_select 'input[type=hidden][name="settings[wiki_approval_settings_sidebar_project]"][value="0"]', 1

      # Sidebar Status multiselect
      assert_select 'input[type=hidden][name="settings[wiki_approval_settings_sidebar_status][]"]', 1
      assert_select 'select[name="settings[wiki_approval_settings_sidebar_status][]"][multiple]', 1

      # alle selected
      %w[canceled draft pending rejected published released].each do |status|
        assert_select "select[name=\"settings[wiki_approval_settings_sidebar_status][]\"] option[value=\"#{status}\"][selected]", 1
      end

      # draft_enabled = true
      assert_select 'select[name="settings[wiki_approval_settings_draft_enabled]"]' do
        assert_select 'option[value="true"][selected]', 1
      end
      # approval_enabled = project
      assert_select 'select[name="settings[wiki_approval_settings_enabled]"]' do
        assert_select 'option[value="project"][selected]', 1
      end
      # approval_required = project
      assert_select 'select[name="settings[wiki_approval_settings_required]"]' do
        assert_select 'option[value="project"][selected]', 1
      end
      # approval_version = true
      assert_select 'select[name="settings[wiki_approval_settings_version]"]' do
        assert_select 'option[value="true"][selected]', 1
      end
    end
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
             wiki_approval_settings_content_draft: 'project',
             wiki_approval_settings_sidebar_project: 'false',
             wiki_approval_settings_sidebar_status: ['', 'draft', 'pending']
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
    assert_equal 'false', Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_sidebar_project]
    assert_equal ['', 'draft', 'pending'], Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_sidebar_status]

    assert_equal 'true', RedmineWikiApproval.safe_setting(:wiki_approval_settings_comment)
    assert_equal 'false', RedmineWikiApproval.safe_setting(:wiki_approval_settings_draft_enabled)
    assert_equal 'project', RedmineWikiApproval.safe_setting(:wiki_approval_settings_enabled)
    assert_equal 'true', RedmineWikiApproval.safe_setting(:wiki_approval_settings_required)
    assert_equal 'false', RedmineWikiApproval.safe_setting(:wiki_approval_settings_version)
    assert_equal 'project', RedmineWikiApproval.safe_setting(:wiki_approval_settings_content_draft)
    assert_equal 'false', RedmineWikiApproval.safe_setting(:wiki_approval_settings_sidebar_project)
    assert_equal ['', 'draft', 'pending'], RedmineWikiApproval.safe_setting(:wiki_approval_settings_sidebar_status)
  end

  def test_project_plugin_settings
    get '/projects/1/settings/wiki_approval'
    assert_response :success
  end

  def default_plugin_settings
    assert_equal 'false', RedmineWikiApproval.safe_setting(:wiki_approval_settings_comment)
    assert_equal 'true', RedmineWikiApproval.safe_setting(:wiki_approval_settings_draft_enabled)
    assert_equal 'project', RedmineWikiApproval.safe_setting(:wiki_approval_settings_enabled)
    assert_equal 'project', RedmineWikiApproval.safe_setting(:wiki_approval_settings_required)
    assert_equal 'true', RedmineWikiApproval.safe_setting(:wiki_approval_settings_version)
    assert_equal 'true', RedmineWikiApproval.safe_setting(:wiki_approval_settings_content_draft)
    assert_equal '0', RedmineWikiApproval.safe_setting(:wiki_approval_settings_sidebar_project)
    assert_equal ['canceled', 'draft', 'pending', 'rejected', 'released', 'canceled', 'published'], RedmineWikiApproval.safe_setting(:wiki_approval_settings_sidebar_status)
  end
end
