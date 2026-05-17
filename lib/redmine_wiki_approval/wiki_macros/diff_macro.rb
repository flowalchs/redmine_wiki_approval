# frozen_string_literal: true

module RedmineWikiApproval
  module WikiMacros
    module DiffMacro
      Redmine::WikiFormatting::Macros.register do
        desc <<-DESCRIPTION
  Displays a link to the diff between the current wiki page version and the latest approved version.

  {{rwa_diff}}

  The diff link is only displayed if:
  - an approval workflow exists for the page
  - the current user is allowed to view wiki revisions

  This macro returns only the diff link itself.
        DESCRIPTION
        macro :rwa_diff do |_obj, _args|
          wiki_approval_diff(
            approval: @wiki_approval_data&.dig(:approval),
            project: @project,
            page: @page,
            view_version_id: @wiki_approval_data&.dig(:view_version_id)
          )
        end
      end
    end
  end
end
