# frozen_string_literal: true

module RedmineWikiApproval
  module Hooks
    class ViewHook < Redmine::Hook::ViewListener
      render_on :view_wiki_show_sidebar_bottom, :partial => "wiki/sidebar_bottom"

      def view_layouts_base_html_head(context)
        if context[:controller].is_a?(WikiController) &&
           (context[:controller].action_name == 'show' || context[:controller].action_name == 'history') &&
           RedmineWikiApproval::Settings.is_enabled?(context[:project])

          # add css stylesheet
          stylesheet_link_tag('wiki_approval', plugin: 'redmine_wiki_approval', media: 'all').html_safe

        end
      end
    end
  end
end
