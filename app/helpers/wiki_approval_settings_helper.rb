# frozen_string_literal: true

module WikiApprovalSettingsHelper
  PROJECT = 'project'

  def wiki_approval_select_options
    options = [
      [:general_text_Yes, 'true'],
      [:general_text_No, 'false'],
      [:label_wiki_approval_settings_projects, PROJECT]
    ]

    options.map {|label, value| [l(label), value.to_s]}
  end

  def view_wiki_settings_tab?(project)
    user = User.current.logged? ? User.current : User.anonymous
    return false unless user.allowed_to?(:wiki_approval_settings, project)

    # indifferent access = Strings
    s = (Setting.plugin_redmine_wiki_approval || {}).with_indifferent_access

    # true, if any is value "project"
    s.values.any? { |v| v.to_s == WikiApprovalSettingsHelper::PROJECT }
  end
end
