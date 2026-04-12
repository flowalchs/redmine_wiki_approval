# frozen_string_literal: true

module RedmineWikiApproval
  module Patches
    module WikiContentPatch
      extend ActiveSupport::Concern

      included do
        prepend InstanceMethods

        validate :validate_approval_comment_required
      end

      module InstanceMethods
        private

        def validate_approval_comment_required
          if comments.blank? && RedmineWikiApproval::Settings.wiki_comment_required?(self.project || self.wiki&.project)
            # error comment required
            errors.add(:comments, :blank)
          end
        end
      end
    end
  end
end
