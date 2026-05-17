# frozen_string_literal: true

module RedmineWikiApproval
  module WikiMacros
    module StatusMacro
      Redmine::WikiFormatting::Macros.register do
        desc <<-DESCRIPTION
  Displays the current approval workflow status of the wiki page.

  {{rwa_status}}
  {{rwa_status(text)}}

  Without arguments, the status is displayed as an HTML badge.
  With the 'text' argument, only the plain status text is returned.
        DESCRIPTION
        macro :rwa_status do |obj, args|
          approval = @wiki_approval_data&.dig(:approval)
          return '' unless approval

          format = args.first == 'text' ? :text : :badge
          wiki_approval_status_value(approval.status, format: format)
        end
      end
    end
  end
end
