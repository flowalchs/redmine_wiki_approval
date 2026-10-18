# frozen_string_literal: true

module RedmineWikiApproval
  module Patches
    module SettingsControllerPatch
      extend ActiveSupport::Concern

      included do
        prepend InstanceOverwriteMethods

        helper :wiki_approval_settings
      end

      module InstanceOverwriteMethods
        # select the plugin entry in the administration menu instead of "Plugins"
        def current_menu_item
          return :redmine_wiki_approval if action_name == 'plugin' && params[:id] == 'redmine_wiki_approval'

          super
        end
      end
    end
  end
end
