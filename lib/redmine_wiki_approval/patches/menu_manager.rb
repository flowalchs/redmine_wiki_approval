# frozen_string_literal: true

module RedmineWikiApproval
  module Patches
    module MenuManager
      def self.register
        Redmine::MenuManager.map :application_menu do |menu|
          menu.push :wiki_approval,
            { controller: 'wiki_approval', action: 'index' },
            caption: :label_wiki,
            if: proc {
              ActiveModel::Type::Boolean.new.cast(RedmineWikiApproval.safe_setting(:wiki_approval_settings_menu)) &&
              User.current.allowed_to?(:view_wiki_pages, nil, global: true) &&
              EnabledModule.exists?(project: Project.visible, name: :wiki_approval)
            }
        end
      end
    end
  end
end
