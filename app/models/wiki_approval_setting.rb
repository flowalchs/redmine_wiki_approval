# frozen_string_literal: true

class WikiApprovalSetting < ApplicationRecord
  self.table_name = 'wiki_approval_settings'
  belongs_to :project
  before_save :sync_data_hash_to_json
  after_save :clear_setting_cache

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
    @bool_settings ||= {}
    @bool_settings[field_name] = setting_key

    define_method(field_name) { resolved_settings[field_name] }

    define_method("#{field_name}=") do |value|
      write_boolean_to_data_hash(field_name, value)
      @resolved_settings = nil
    end
  end

  def self.setting_array(project_key, global_key, field_name:)
    @array_settings ||= {}
    @array_settings[field_name] = { project_key: project_key, global_key: global_key }

    define_method(field_name) { resolved_settings[field_name] }

    define_method("#{field_name}=") do |value|
      data_hash[field_name] = Array(value || '')
      @resolved_settings = nil
    end
  end

  def self.bool_settings
    @bool_settings || {}
  end

  def self.array_settings
    @array_settings || {}
  end

  # DSL USAGE
  setting_bool :wiki_approval_settings_required,        field_name: :wiki_approval_required
  setting_bool :wiki_approval_settings_version,         field_name: :wiki_approval_version
  setting_bool :wiki_approval_settings_enabled,         field_name: :wiki_approval_enabled
  setting_bool :wiki_approval_settings_content_draft,   field_name: :wiki_content_draft
  setting_bool :wiki_approval_settings_comment,         field_name: :wiki_comment_required
  setting_bool :wiki_approval_settings_draft_enabled,   field_name: :wiki_draft_enabled

  setting_array(:wiki_approval_settings_sidebar_project, :wiki_approval_settings_sidebar_status, field_name: :wiki_sidebar_status)
  setting_array(:wiki_approval_settings_templates, :wiki_approval_settings_templates, field_name: :wiki_templates)

  # Convenience-Methoden
  def approval_or_draft_enabled?
    wiki_approval_enabled || wiki_draft_enabled
  end

  def requires_approval?
    wiki_approval_required || wiki_approval_version
  end

  def draft_active?
    wiki_draft_enabled || wiki_approval_enabled
  end

  def content_draft_for?(user)
    user.allowed_to?(:edit_wiki_pages, project) && wiki_content_draft
  end

  private

  def sync_data_hash_to_json
    self.json_data = @data_hash.to_json if @data_hash
  end

  def resolved_settings
    @resolved_settings ||= {}.tap do |h|
      self.class.bool_settings.each do |field_name, setting_key|
        h[field_name] = resolve_bool(setting_key, data_hash[field_name])
      end

      self.class.array_settings.each do |field_name, keys|
        h[field_name] = project_or_global_array(keys[:project_key], keys[:global_key], data_hash[field_name])
      end
    end
  end

  def resolve_bool(setting_key, data_value)
    setting = RedmineWikiApproval.safe_setting(setting_key)
    value = setting == WikiApprovalSettingsHelper::PROJECT ? data_value : setting
    ActiveModel::Type::Boolean.new.cast(value)
  end

  def project_or_global_array(project_key, global_key, data_value)
    project_setting = RedmineWikiApproval.safe_setting(project_key)

    unless project_setting.is_a?(Array)
      project_enabled = ActiveModel::Type::Boolean.new.cast(project_setting)
      return RedmineWikiApproval.safe_setting(global_key) unless project_enabled
    end

    if data_value.is_a?(Array)
      global = Array(RedmineWikiApproval.safe_setting(global_key))
      data_value = Array(data_value) & global
    end

    project_value_or_default(global_key, data_value)
  end

  def write_boolean_to_data_hash(key, value)
    data_hash[key] = ActiveModel::Type::Boolean.new.cast(value || '0')
  end

  def project_value_or_default(global_key, data_value)
    return Array(data_value).reject(&:blank?) unless data_value.nil?

    case global_key.to_s
    when 'wiki_approval_settings_templates'
      RedmineWikiApproval::WikiTemplates::ENABLED_TEMPLATE_TYPES
    when 'wiki_approval_settings_sidebar_status'
      ['canceled', 'draft', 'pending', 'rejected']
    else
      data_value
    end
  end

  def clear_setting_cache
    @resolved_settings = nil
    @data_hash = nil
  end
end
