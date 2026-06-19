# frozen_string_literal: true

module RedmineWikiApproval
  class Current < ActiveSupport::CurrentAttributes
    attribute :workflow_is_draft
    attribute :wiki_approval_data
  end
end
