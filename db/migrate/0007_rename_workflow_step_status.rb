# frozen_string_literal: true

class RenameWorkflowStepStatus < ActiveRecord::Migration[5.2]
  def up
    remove_index :wiki_approval_workflow_steps, :status if index_exists?(:wiki_approval_workflow_steps, :status)
    rename_column :wiki_approval_workflow_steps, :status, :step_status
    add_index :wiki_approval_workflow_steps, :step_status
  end

  def down
    remove_index :wiki_approval_workflow_steps, :step_status if index_exists?(:wiki_approval_workflow_steps, :step_status)
    rename_column :wiki_approval_workflow_steps, :step_status, :status
    add_index :wiki_approval_workflow_steps, :status
  end
end
