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

  def wiki_approval_select_field(setting_key, value: nil, field_name: nil, html_options: {}, options: nil)
    setting_key = setting_key.to_s
    multiple = html_options[:multiple] == true
    field_name ||= "settings[#{setting_key}]" if field_name.nil?
    value ||= RedmineWikiApproval.safe_setting(setting_key) if value.nil?
    value = Array(value) if multiple
    field_name = "#{field_name}[]" if multiple
    options ||= wiki_approval_select_options if options.nil?

    content_tag(:p) do
      label = content_tag(:label, l("label_#{setting_key}"))
      hidden = multiple ? hidden_field_tag(field_name, '') : ''.html_safe

      select = select_tag(
        field_name,
        options_for_select(options, value),
        html_options.reverse_merge(id: setting_key)
      )

      info_key = "text_#{setting_key}"
      info = if I18n.exists?(info_key)
               content_tag(:em, t(info_key), class: "info")
             else
               "".html_safe
             end

      label + hidden + select + info
    end
  end

  def wiki_approval_checkbox_field(setting_key, value: nil, field_name: nil, html_options: {})
    return ''.html_safe if field_name && RedmineWikiApproval.safe_setting(setting_key) != WikiApprovalSettingsHelper::PROJECT

    field_name ||= "settings[#{setting_key}]" if field_name.nil?
    value ||= ActiveModel::Type::Boolean.new.cast(RedmineWikiApproval.safe_setting(setting_key)) if value.nil?

    content_tag(:p) do
      hidden = hidden_field_tag(field_name, '0')

      checkbox = check_box_tag(
        field_name,
        '1',
        value,
        html_options.reverse_merge(id: setting_key)
      )

      label = label_tag(:label, l("label_#{setting_key}"))

      info_key = "text_#{setting_key}"
      info = if I18n.exists?(info_key)
               content_tag(:em, t(info_key), class: "info")
             else
               "".html_safe
             end

      hidden + checkbox + label + info
    end
  end

  def wiki_approval_sidebar_status_select_options
    WikiApprovalWorkflow.statuses.keys.map { |k| [l("wiki_approval_workflow.status.#{k}"), k] }
  end

  def wiki_approval_templates_select_options(settings = nil)
    types = RedmineWikiApproval::WikiTemplates::ENABLED_TEMPLATE_TYPES

    return types if settings.blank?

    Array(settings).map(&:to_s) & types
  end

  def setting_array_present?(value)
    Array(value).any?(&:present?)
  end
end
