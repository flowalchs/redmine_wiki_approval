# frozen_string_literal: true

class AddApprovedPageIdToApprovalWorkflow < ActiveRecord::Migration[5.2]
  def up
    add_column :wiki_approval_workflows, :approved_page_id, :integer
    add_index :wiki_approval_workflows, :approved_page_id,
              unique: true,
              name: "idx_waw_approved_page_id"
  end

  def down
    remove_index :wiki_approval_workflows, name: "idx_waw_approved_page_id"
    remove_column :wiki_approval_workflows, :approved_page_id
  end
end
