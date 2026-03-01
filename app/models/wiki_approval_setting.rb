# frozen_string_literal: true

class WikiApprovalSetting < ApplicationRecord
  self.table_name = 'wiki_approval_settings'
  belongs_to :project
  before_save :sync_data_hash_to_json

  def self.find_or_create(pj_id)
    setting = WikiApprovalSetting.find_by(project_id: pj_id)
    unless setting
      setting = WikiApprovalSetting.new
      setting.project_id = pj_id
      setting.save!
    end
    return setting
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

  # Getter with default value, or setting from projecct
  def wiki_comment_required
    if Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_comment] == WikiApprovalSettingsHelper::PROJECT
      ActiveModel::Type::Boolean.new.cast(data_hash[:wiki_comment_required])
    else
      ActiveModel::Type::Boolean.new.cast(Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_comment])
    end
  end

  def wiki_comment_required=(value)
    data_hash[:wiki_comment_required] = ActiveModel::Type::Boolean.new.cast(value)
  end

  def wiki_draft_enabled
    if Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_draft_enabled] == WikiApprovalSettingsHelper::PROJECT
      ActiveModel::Type::Boolean.new.cast(data_hash[:wiki_draft_enabled])
    else
      ActiveModel::Type::Boolean.new.cast(Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_draft_enabled])
    end
  end

  def wiki_draft_enabled=(value)
    data_hash[:wiki_draft_enabled] = ActiveModel::Type::Boolean.new.cast(value)
  end

  def wiki_approval_enabled
    if Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_enabled] == WikiApprovalSettingsHelper::PROJECT
      ActiveModel::Type::Boolean.new.cast(data_hash[:wiki_approval_enabled])
    else
      ActiveModel::Type::Boolean.new.cast(Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_enabled])
    end
  end

  def wiki_approval_enabled=(value)
    data_hash[:wiki_approval_enabled] = ActiveModel::Type::Boolean.new.cast(value)
  end

  def wiki_approval_required
    if Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_required] == WikiApprovalSettingsHelper::PROJECT
      ActiveModel::Type::Boolean.new.cast(data_hash[:wiki_approval_required])
    else
      ActiveModel::Type::Boolean.new.cast(Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_required])
    end
  end

  def wiki_approval_required=(value)
    data_hash[:wiki_approval_required] = ActiveModel::Type::Boolean.new.cast(value)
  end

  def wiki_approval_version
    if Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_version] == WikiApprovalSettingsHelper::PROJECT
      ActiveModel::Type::Boolean.new.cast(data_hash[:wiki_approval_version])
    else
      ActiveModel::Type::Boolean.new.cast(Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_version])
    end
  end

  def wiki_approval_version=(value)
    data_hash[:wiki_approval_version] = ActiveModel::Type::Boolean.new.cast(value)
  end

  def wiki_content_draft
    if Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_content_draft] == WikiApprovalSettingsHelper::PROJECT
      ActiveModel::Type::Boolean.new.cast(data_hash[:wiki_content_draft])
    else
      ActiveModel::Type::Boolean.new.cast(Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_content_draft])
    end
  end

  def wiki_content_draft=(value)
    data_hash[:wiki_content_draft] = ActiveModel::Type::Boolean.new.cast(value)
  end

  private

  def sync_data_hash_to_json
    self.json_data = @data_hash.to_json if @data_hash
  end
end
