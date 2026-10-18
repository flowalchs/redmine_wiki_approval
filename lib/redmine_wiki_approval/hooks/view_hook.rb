# frozen_string_literal: true

module RedmineWikiApproval
  module Hooks
    class ViewHook < Redmine::Hook::ViewListener
      render_on :view_wiki_show_sidebar_bottom, :partial => "wiki/sidebar_bottom"

      def view_layouts_base_html_head(context)
        return unless load_wiki_approval_css?(context)

        # add css stylesheet
        stylesheet_link_tag('wiki_approval', plugin: 'redmine_wiki_approval', media: 'all').html_safe
      end

      private

      def load_wiki_approval_css?(context)
        controller = context[:controller]

        return true if controller.is_a?(WikiApprovalController) &&
                       controller.action_name == 'index'

        controller.is_a?(WikiController) &&
          controller.action_name.in?(%w[show history]) &&
          RedmineWikiApproval::Settings.is_enabled?(context[:project])
      end
    end
  end
end
