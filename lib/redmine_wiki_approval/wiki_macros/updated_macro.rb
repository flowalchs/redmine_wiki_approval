# frozen_string_literal: true

module RedmineWikiApproval
  module WikiMacros
    module UpdatedMacro
      Redmine::WikiFormatting::Macros.register do
        desc <<-DESCRIPTION
  Displays the last update timestamp of the current wiki approval workflow.

  {{rwa_updated_at}}
  {{rwa_updated_at(relative)}}

  Without arguments, the timestamp is displayed using Redmine's date and time format.
  With the 'relative' argument, a relative time is shown with a tooltip containing the exact timestamp.
        DESCRIPTION
        macro :rwa_updated_at do |obj, args|
          approval = @wiki_approval_data&.dig(:approval)
          updated_at = approval&.updated_at
          return '' unless updated_at

          format = args.first == 'relative' ? :relative : nil
          wiki_approval_time(approval.updated_at, format: format)
        end
      end
    end
  end
end
