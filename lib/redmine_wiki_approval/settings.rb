# frozen_string_literal: true

module RedmineWikiApproval
  class Settings
    class << self
      def is_enabled?(project)
        return false unless project

        project.module_enabled? 'wiki_approval'
      end

      def draft_create?(project, setting = nil)
        return false unless project
        return false if setting.nil? && !is_enabled?(project)

        setting ||= WikiApprovalSetting.find_or_create(project.id)
        return true if setting.wiki_approval_required || setting.wiki_approval_version
        return true if setting.wiki_draft_enabled == false && setting.wiki_approval_enabled
        return false unless setting.wiki_draft_enabled

        user = User.current.logged? ? User.current : User.anonymous
        user.allowed_to?(:edit_wiki_pages, project)
      end

      def approval_start?(project, setting = nil)
        return false unless project
        return false if setting.nil? && !is_enabled?(project)

        setting ||= WikiApprovalSetting.find_or_create(project.id)
        return false unless setting.wiki_approval_enabled

        user = User.current.logged? ? User.current : User.anonymous
        user.allowed_to?(:wiki_approval_start, project)
      end

      def is_allowed_to_show_last_version?(project)
        return false unless approval_or_draft_enabled?(project)

        user = User.current.logged? ? User.current : User.anonymous
        user.allowed_to?(:view_wiki_edits, project)
      end

      def approval_enabled?(project, setting = nil)
        return false unless project
        return false if setting.nil? && !is_enabled?(project)

        setting ||= WikiApprovalSetting.find_or_create(project.id)
        return setting.wiki_approval_enabled
      end

      def approval_publish?(project, setting = nil)
        return false unless project
        return false if setting.nil? && !is_enabled?(project)

        setting ||= WikiApprovalSetting.find_or_create(project.id)
        user = User.current.logged? ? User.current : User.anonymous
        return user.allowed_to?(:wiki_approval_publish, project) && setting.wiki_draft_enabled
      end

      def approval_or_draft_enabled?(project, setting = nil)
        return false unless project
        return false if setting.nil? && !is_enabled?(project)

        setting ||= WikiApprovalSetting.find_or_create(project.id)
        return setting.wiki_approval_enabled || setting.wiki_draft_enabled
      end

      def wiki_comment_required?(project, setting = nil)
        return false unless project
        return false if setting.nil? && !is_enabled?(project)

        setting ||= WikiApprovalSetting.find_or_create(project.id)
        return setting.wiki_comment_required
      end

      def view_draft?(project, setting = nil)
        return false unless is_allowed_to_show_last_version?(project)

        user = User.current.logged? ? User.current : User.anonymous
        user.allowed_to?(:wiki_draft_view, project) || user.allowed_to?(:wiki_approval_grant, project)
      end

      def content_draft?(project, setting = nil)
        return false unless project
        return false if setting.nil? && !is_enabled?(project)

        setting ||= WikiApprovalSetting.find_or_create(project.id)
        user = User.current.logged? ? User.current : User.anonymous
        return user.allowed_to?(:edit_wiki_pages, project) && setting.wiki_content_draft
      end
    end
  end
end
