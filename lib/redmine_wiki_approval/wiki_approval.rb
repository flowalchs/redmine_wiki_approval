# frozen_string_literal: true

module RedmineWikiApproval
  class WikiApproval
    class << self
      def wiki_approval_ui_status_draft(page:, approval:, setting:)
        disabled =
          setting.wiki_approval_required ||
          (
            setting.wiki_approval_version &&
            WikiApprovalWorkflow.latest_public_version_status(page.id, :released)
          )

        default =
          disabled ||
          (
            approval &&
            approval.status.in?(%w[pending rejected draft])
          )

        status_hidden = disabled ? "draft" : "published"

        # special case
        if setting.wiki_draft_enabled == false &&
            setting.wiki_approval_enabled &&
            setting.wiki_approval_required == false &&
            setting.wiki_approval_version == false

          disabled      = true
          default       = false
          status_hidden = "published"
        end

        {
          approval_required: disabled,
          checked: default,
          status: status_hidden
        }
      end
    end
  end
end
