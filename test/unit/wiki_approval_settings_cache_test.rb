# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class WikiApprovalSettingsCacheTest < WikiApproval::Test::UnitCase
  SETTINGS = RedmineWikiApproval::Settings

  def setup
    super
    RedmineWikiApproval::Current.reset
  end

  def test_project_setting_is_loaded_once_per_request
    first = SETTINGS.project_setting(@project)
    assert_same first, SETTINGS.project_setting(@project)
    assert_equal @project.id, first.project_id
  end

  def test_project_setting_is_cached_per_project
    assert_not_same SETTINGS.project_setting(@project), SETTINGS.project_setting(@project3)
  end

  def test_project_setting_without_project
    assert_nil SETTINGS.project_setting(nil)
  end

  def test_project_setting_cache_is_cleared_after_save
    cached = SETTINGS.project_setting(@project)
    WikiApprovalSetting.find_by(project_id: @project.id).update!(json_data: { wiki_comment_required: true }.to_json)

    assert_not_same cached, SETTINGS.project_setting(@project)
  end

  def test_project_setting_cache_is_cleared_only_for_saved_project
    other = SETTINGS.project_setting(@project3)
    SETTINGS.project_setting(@project).save!

    assert_same other, SETTINGS.project_setting(@project3)
  end

  def test_project_setting_cache_is_invalid_after_global_settings_change
    with_wiki_approval_settings(wiki_approval_settings_comment: '0') do
      assert_equal false, SETTINGS.project_setting(@project).wiki_comment_required

      # without Current.reset, like a settings change during the same thread
      with_wiki_approval_settings(wiki_approval_settings_comment: '1') do
        assert_equal true, SETTINGS.project_setting(@project).wiki_comment_required
      end
    end
  end

  def test_project_setting_cache_is_reset_with_current
    cached = SETTINGS.project_setting(@project)
    RedmineWikiApproval::Current.reset
    assert_not_same cached, SETTINGS.project_setting(@project)
  end

  def test_settings_methods_without_setting_use_cache
    calls = 0
    counter = Module.new do
      define_method(:find_or_create) do |*args|
        calls += 1
        super(*args)
      end
    end
    WikiApprovalSetting.singleton_class.prepend(counter)

    SETTINGS.wiki_comment_required?(@project)
    SETTINGS.approval_enabled?(@project)
    SETTINGS.wiki_templates(@project)
    assert_equal 1, calls
  end
end
