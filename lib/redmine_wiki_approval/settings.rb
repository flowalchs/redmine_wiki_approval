# frozen_string_literal: true

module RedmineWikiApproval
  class Settings
    class << self
      def is_enabled?(project)
        return false unless project

        project.module_enabled? 'wiki_approval'
      end

      def draft_create?(project, setting = nil)
        s = resolve_setting(project, setting)
        return false unless s

        return true if s.requires_approval?
        return true if s.wiki_draft_enabled == false && s.wiki_approval_enabled
        return false unless s.wiki_draft_enabled

        current_user.allowed_to?(:edit_wiki_pages, project)
      end

      def approval_start?(project, setting = nil)
        s = resolve_setting(project, setting)
        return false unless s
        return false unless s.wiki_approval_enabled

        current_user.allowed_to?(:wiki_approval_start, project)
      end

      def is_allowed_to_show_last_version?(project, setting = nil)
        s = resolve_setting(project, setting)
        return false unless s
        return false unless s.approval_or_draft_enabled?

        current_user.allowed_to?(:view_wiki_edits, project)
      end

      def approval_enabled?(project, setting = nil)
        s = resolve_setting(project, setting)
        s&.wiki_approval_enabled || false
      end

      def approval_publish?(project, setting = nil)
        s = resolve_setting(project, setting)
        return false unless s

        current_user.allowed_to?(:wiki_approval_publish, project) && s.wiki_draft_enabled
      end

      def approval_or_draft_enabled?(project, setting = nil)
        s = resolve_setting(project, setting)
        s&.approval_or_draft_enabled? || false
      end

      def wiki_comment_required?(project, setting = nil)
        s = resolve_setting(project, setting)
        s&.wiki_comment_required || false
      end

      def view_draft?(project, setting = nil)
        return false unless is_allowed_to_show_last_version?(project, setting)

        current_user.allowed_to?(:wiki_draft_view, project) || current_user.allowed_to?(:wiki_approval_grant, project)
      end

      def content_draft?(project, setting = nil)
        s = resolve_setting(project, setting)
        return false unless s

        s.content_draft_for?(current_user)
      end

      def comments_enabled?(project, setting = nil)
        s = resolve_setting(project, setting)
        s&.wiki_comments || false
      end

      def view_comments?(project, setting = nil)
        return false unless comments_enabled?(project, setting)

        current_user.allowed_to?(:wiki_comments_view, project)
      end

      def add_comments?(project, setting = nil)
        return false unless comments_enabled?(project, setting)
        return false unless current_user.logged?

        current_user.allowed_to?(:wiki_comments_add, project)
      end

      def wiki_templates(project, setting = nil)
        s = resolve_setting(project, setting)
        return [] unless s

        Array(s.wiki_templates).select(&:present?)
      end

      # project setting, loaded once per request
      def project_setting(project)
        return nil unless project

        cache = RedmineWikiApproval::Current.project_settings ||= {}
        # the global plugin settings hash is replaced when they change,
        # so cached project settings with old resolved values are not reused
        key = [project.id, Setting.plugin_redmine_wiki_approval.object_id]
        cache[key] ||= WikiApprovalSetting.find_or_create(project.id)
      end

      def clear_project_setting_cache(project_id = nil)
        cache = RedmineWikiApproval::Current.project_settings
        return unless cache

        project_id ? cache.delete_if { |key, _| key.first == project_id } : cache.clear
      end

      private

      def resolve_setting(project, setting)
        return nil unless project
        return setting if setting.present?
        return nil unless is_enabled?(project)

        project_setting(project)
      end

      def current_user
        User.current.logged? ? User.current : User.anonymous
      end
    end
  end
end
