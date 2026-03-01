# frozen_string_literal: true

class WikiApprovalDraft < ApplicationRecord
  self.table_name = 'wiki_approval_draft'

  belongs_to :wiki_page
  belongs_to :author, class_name: 'User'

  def status
    :draft_in_progress
  end

  def note
    nil
  end

  def wiki_version_id
    self.wiki_page.version
  end
end
