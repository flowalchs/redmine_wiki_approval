# frozen_string_literal: true

module RedmineWikiApproval
  module Hooks
    class ViewHook < Redmine::Hook::ViewListener
      render_on :view_wiki_show_sidebar_bottom, :partial => "wiki/sidebar_bottom"

      def view_layouts_base_html_head(context)
        if context[:controller].is_a?(WikiController) &&
           context[:controller].action_name == 'show' &&
           RedmineWikiApproval.is_enabled?(context[:project])

          if RedmineWikiApproval.is_allowed_to_show_last_version?(context[:project]) &&
             !from_update?(context[:controller])

            controller = context[:controller]
            page = controller.instance_variable_get(:@page)

            # when accessing the current wiki page
            if controller.params[:version].nil? && page&.version
              version_nr = WikiApprovalWorkflow.latest_public_version_nr(page)

              # Redirect only if the last public versions differ
              if version_nr.present? && version_nr != page.version

                context[:controller].redirect_to(
                  controller: 'wiki',
                  action: 'show',
                  project_id: context[:controller].params[:project_id],
                  id: page.title,
                  version: version_nr
                )
                return

              end

            end

            # If the current page is in draft or approval status and there are no rights to view the draft, then this is not authorized.
            version = controller.params[:version]&.to_i || page&.version
            if version &&
              RedmineWikiApproval.view_draft?(context[:project]) == false &&
              (WikiApprovalWorkflow.for_wiki(page.id, version).first&.status_before_type_cast&.< WikiApprovalWorkflow.statuses[:published])
              raise ::Unauthorized
            end
          end

          # add css stylesheet
          stylesheet_link_tag('wiki_approval', plugin: 'redmine_wiki_approval', media: 'all').html_safe

        end
      end

      private

      def from_update?(controller)
        referer = controller.request.referer
        referer.present? && referer.include?('/wiki/') && referer.include?('edit')
      end
    end
  end
end
