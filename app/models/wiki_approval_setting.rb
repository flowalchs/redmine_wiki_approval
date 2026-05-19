# frozen_string_literal: true

class WikiApprovalSetting < ApplicationRecord
  self.table_name = 'wiki_approval_settings'
  belongs_to :project
  before_save :sync_data_hash_to_json

  def self.find_or_create(pj_id)
    find_or_create_by!(project_id: pj_id)
  end

  def data_hash
    @data_hash ||= begin
      parsed = JSON.parse(json_data.presence || '{}', symbolize_names: true)
      parsed.is_a?(Hash) ? parsed.deep_dup : {}
    rescue JSON::ParserError
      {}
    end
  end

  def data_hash=(hash)
    self.json_data = hash.to_json
    @data_hash = hash
  end

  # DSL DEFINITIONS
  def self.setting_bool(setting_key, field_name:)
    define_method(field_name) do
      project_or_global_bool(setting_key, data_hash[field_name])
    end

    define_method("#{field_name}=") do |value|
      write_boolean_to_data_hash(field_name, value)
    end
  end

  def self.setting_array(project_key, global_key, field_name:)
    define_method(field_name) do
      project_or_global_array(project_key, global_key, data_hash[field_name])
    end

    define_method("#{field_name}=") do |value|
      data_hash[field_name] = Array(value || '')
    end
  end

  # DSL USAGE
  # Getter/Setter with default value, or setting from projecct

  setting_bool :wiki_approval_settings_required,        field_name: :wiki_approval_required
  setting_bool :wiki_approval_settings_version,         field_name: :wiki_approval_version
  setting_bool :wiki_approval_settings_enabled,         field_name: :wiki_approval_enabled
  setting_bool :wiki_approval_settings_content_draft,   field_name: :wiki_content_draft
  setting_bool :wiki_approval_settings_comment,         field_name: :wiki_comment_required
  setting_bool :wiki_approval_settings_draft_enabled,   field_name: :wiki_draft_enabled

  setting_array(
    :wiki_approval_settings_sidebar_project,
    :wiki_approval_settings_sidebar_status,
    field_name: :wiki_sidebar_status
  )

  private

  def sync_data_hash_to_json
    self.json_data = @data_hash.to_json if @data_hash
  end

  def project_or_global_bool(setting_key, data_value)
    setting = RedmineWikiApproval.safe_setting(setting_key)
    value =
      if setting == WikiApprovalSettingsHelper::PROJECT
        data_value
      else
        setting
      end

    ActiveModel::Type::Boolean.new.cast(value)
  end

  def project_or_global_array(project_key, global_key, data_value)
    project_enabled = ActiveModel::Type::Boolean.new.cast(
      RedmineWikiApproval.safe_setting(project_key)
    )

    value =
      if project_enabled
        # not nil for sidebar status in projects
        if data_value.nil? && global_key.to_s == 'wiki_approval_settings_sidebar_status'
          ['', 'canceled', 'draft', 'pending', 'rejected']
        else
          data_value
        end
      else
        RedmineWikiApproval.safe_setting(global_key)
      end

    Array(value).map(&:to_s)
  end

  def write_boolean_to_data_hash(key, value)
    data_hash[key] = ActiveModel::Type::Boolean.new.cast(value || '0')
  end
end
