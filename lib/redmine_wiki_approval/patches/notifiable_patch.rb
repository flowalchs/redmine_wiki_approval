# frozen_string_literal: true

module RedmineWikiApproval
  module Patches
    module NotifiablePatch
      extend ActiveSupport::Concern

      def all
        notifications = super
        notifications << Redmine::Notifiable.new('wiki_approval_notifications')
        notifications << Redmine::Notifiable.new('wiki_comment_added')
        notifications << Redmine::Notifiable.new('wiki_comment_status_changed')
        notifications
      end
    end
  end
end
