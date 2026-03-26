# frozen_string_literal: true

class AddIndexCreatedWorkflowStatuses < ActiveRecord::Migration[5.2]
  def up
    add_index :wiki_approval_workflow_statuses, :created_at, name: "idx_approval_workflow_statuses_created"
  end

  def down
    remove_index :wiki_approval_workflow_statuses, :created_at, name: "idx_approval_workflow_statuses_created"
  end
end
