# frozen_string_literal: true

require 'redmine_plugin_kit'

module RedmineWikiApproval
  VERSION = '0.13.0'

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
                          WikiContent]

      loader.add_helper [{ controller: 'Settings', helper: 'WikiApprovalSettings' },
                         { controller: 'Projects', helper: 'WikiApprovalSettings' }]

      Redmine::Notifiable.singleton_class.prepend RedmineWikiApproval::Patches::NotifiablePatch

      loader.apply!

      loader.load_macros!

      loader.load_view_hooks!
    end
  end
end
