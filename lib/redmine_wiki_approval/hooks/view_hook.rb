# frozen_string_literal: true

module RedmineWikiApproval
  module Hooks
    class ViewHook < Redmine::Hook::ViewListener
      def view_wiki_show_sidebar_bottom(context)
        view = context[:hook_caller]
        safe_join(%w[wiki/sidebar_bottom wiki_approval_comments/show_sidebar].map do |partial|
          view.render(partial: partial, locals: context)
        end)
      end

      def view_layouts_base_html_head(context)
        return unless load_wiki_approval_css?(context)

        # add css stylesheet
        tags = stylesheet_link_tag('wiki_approval', plugin: 'redmine_wiki_approval', media: 'all')
        if load_wiki_comments_js?(context)
          tags += javascript_include_tag('wiki_approval_comments', plugin: 'redmine_wiki_approval', type: 'module')
        end
        tags.html_safe
      end

      private

      def load_wiki_comments_js?(context)
        controller = context[:controller]

        controller.is_a?(WikiController) &&
          controller.action_name == 'show' &&
          RedmineWikiApproval::Settings.view_comments?(context[:project])
      end

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
