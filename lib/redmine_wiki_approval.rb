# frozen_string_literal: true

require 'redmine_plugin_kit'

module RedmineWikiApproval
  VERSION = '1.0.0'

  include RedminePluginKit::PluginBase

  class << self
    def safe_setting(key)
      setting(key.to_sym)
    end

    private

    def setup
      loader.add_patch %w[ProjectsHelper
                          WikiController
                          WikiContentVersion
                          WikiPage
                          WikiContent
                          QueriesController
                          SettingsController]

      # Settings helper is added in SettingsControllerPatch
      loader.add_helper [{ controller: 'Projects', helper: 'WikiApprovalSettings' }]

      Redmine::Notifiable.singleton_class.prepend RedmineWikiApproval::Patches::NotifiablePatch

      RedmineWikiApproval::Patches::MenuManager.register

      loader.apply!
      loader.load_macros!
      loader.load_view_hooks!
    end
  end
end
