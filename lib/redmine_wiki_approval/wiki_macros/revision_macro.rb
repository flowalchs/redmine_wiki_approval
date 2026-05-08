# frozen_string_literal: true

module RedmineWikiApproval
  module WikiMacros
    module RevisionMacro
      Redmine::WikiFormatting::Macros.register do
        desc <<-DESCRIPTION
  Displays the approved revision number of the current wiki page.

  {{rwa_revision}}
        DESCRIPTION
        macro :rwa_revision do |obj, args|
          @wiki_approval_data&.dig(:approval)&.revision || ''
        end
      end
    end
  end
end
