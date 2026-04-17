# frozen_string_literal: true

class WikiApprovalDraft < ApplicationRecord
  self.table_name = 'wiki_approval_draft'

  belongs_to :wiki_page, foreign_key: :page_id
  belongs_to :author, class_name: 'User'

  def status
    :draft_in_progress
  end

  def note
    nil
  end
end
