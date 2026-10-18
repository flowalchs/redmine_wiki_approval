# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class WikiApprovalMenuTest < WikiApproval::Test::UnitCase
  MENU = RedmineWikiApproval::Patches::MenuManager

  def setup
    super
    RedmineWikiApproval::Current.reset
  end

  def teardown
    RedmineWikiApproval::Current.reset
    super
  end

  def test_visible_with_setting_and_permission
    User.current = @jsmith
    with_wiki_approval_settings(wiki_approval_settings_list_application_menu: '1') do
      assert MENU.wiki_list_visible?(:wiki_approval_settings_list_application_menu)
    end
  end

  def test_hidden_when_setting_is_disabled
    User.current = @jsmith
    with_wiki_approval_settings(wiki_approval_settings_list_top_menu: '0') do
      assert_not MENU.wiki_list_visible?(:wiki_approval_settings_list_top_menu)
    end
  end

  def test_hidden_without_wiki_approval_module
    User.current = @jsmith
    EnabledModule.where(name: 'wiki_approval').delete_all
    with_wiki_approval_settings(wiki_approval_settings_list_application_menu: '1') do
      assert_not MENU.wiki_list_visible?(:wiki_approval_settings_list_application_menu)
    end
  end

  def test_hidden_without_permission
    User.current = User.anonymous
    [Role.anonymous, Role.non_member].each { |role| role.remove_permission!(:view_wiki_pages) }
    with_wiki_approval_settings(wiki_approval_settings_list_application_menu: '1') do
      assert_not MENU.wiki_list_visible?(:wiki_approval_settings_list_application_menu)
    end
  end

  def test_visibility_is_cached_per_request
    User.current = @jsmith
    with_wiki_approval_settings(wiki_approval_settings_list_application_menu: '1',
                                wiki_approval_settings_list_top_menu: '1') do
      assert MENU.wiki_list_visible?(:wiki_approval_settings_list_application_menu)
      EnabledModule.where(name: 'wiki_approval').delete_all
      assert MENU.wiki_list_visible?(:wiki_approval_settings_list_top_menu)

      RedmineWikiApproval::Current.reset
      assert_not MENU.wiki_list_visible?(:wiki_approval_settings_list_top_menu)
    end
  end
end
