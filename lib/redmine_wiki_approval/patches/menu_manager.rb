# frozen_string_literal: true

module RedmineWikiApproval
  module Patches
    module MenuManager
      def self.register
        Redmine::MenuManager.map :top_menu do |menu|
          menu.push :wiki_approval,
            { controller: 'wiki_approval', action: 'index' },
            caption: :label_wiki,
            if: proc { MenuManager.wiki_list_visible?(:wiki_approval_settings_list_top_menu) }
        end

        Redmine::MenuManager.map :application_menu do |menu|
          menu.push :wiki_approval,
            { controller: 'wiki_approval', action: 'index' },
            caption: :label_wiki,
            if: proc { MenuManager.wiki_list_visible?(:wiki_approval_settings_list_application_menu) }
        end
      end

      def self.wiki_list_visible?(setting_key)
        return false unless RedmineWikiApproval.setting?(setting_key)

        # permission check is cached per request, both menus share it
        if RedmineWikiApproval::Current.wiki_list_visible.nil?
          RedmineWikiApproval::Current.wiki_list_visible =
            User.current.allowed_to?(:view_wiki_pages, nil, global: true)
        end
        RedmineWikiApproval::Current.wiki_list_visible
      end
    end
  end
end
