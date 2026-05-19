# frozen_string_literal: true

require 'redmine_plugin_kit'

module RedmineWikiApproval
  VERSION = '0.12.0'

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

      loader.add_global_helper [
        WikiApprovalSettingsHelper,
        WikiApprovalIconHelper,
        WikiApprovalHelper
      ]

      loader.apply!

      loader.load_macros!

      loader.load_view_hooks!
    end
  end
end
