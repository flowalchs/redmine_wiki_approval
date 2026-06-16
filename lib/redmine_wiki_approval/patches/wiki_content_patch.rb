# frozen_string_literal: true

module RedmineWikiApproval
  module Patches
    module WikiContentPatch
      extend ActiveSupport::Concern

      included do
        prepend InstanceMethods

        validate :validate_approval_comment_required
        validate :validate_template_permission
      end

      module InstanceMethods
        private

        def validate_approval_comment_required
          if comments.blank? && RedmineWikiApproval::Settings.wiki_comment_required?(self.project || self.wiki&.project)
            # error comment required
            errors.add(:comments, :blank)
          end
        rescue => e
          Rails.logger.error("validate_approval_comment_required plugin rwa fallback: #{e.class} - #{e.message}")
        end

        def validate_template_permission
          return if page.blank?

          service = RedmineWikiApproval::WikiTemplates.new(
            project: self.project || self.wiki&.project,
            user: User.current,
            setting: nil
          )
          return unless service.template?(page: page)

          unless service.user_can_edit_template?(page: page)
            errors.add(:base, l(:no_wiki_template_permission))
          end
        rescue => e
          Rails.logger.error("validate_template_permission plugin rwa fallback: #{e.class} - #{e.message}")
        end
      end
    end
  end
end
