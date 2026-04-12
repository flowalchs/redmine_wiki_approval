class AddCurrentPageIdApprovalWorkflow < ActiveRecord::Migration[5.2]
  def up
    # We are adding the column. It is NULL by default. Only filled in the current version
    add_column :wiki_approval_workflows, :current_page_id, :integer
    # Index allows only one entry per page_id that is NOT NULL.
    add_index :wiki_approval_workflows, :current_page_id, unique: true, name: "idx_waw_current_page_id"
  end

  def down
    remove_index :wiki_approval_workflows, name: "idx_waw_current_page_id"
    remove_column :wiki_approval_workflows, :current_page_id
  end
end
