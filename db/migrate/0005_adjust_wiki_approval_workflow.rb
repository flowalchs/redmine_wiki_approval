# frozen_string_literal: true

class AdjustWikiApprovalWorkflow < ActiveRecord::Migration[5.2]
  def up
    remove_foreign_key :wiki_approval_workflows, :wiki_pages
    remove_index :wiki_approval_workflows, name: "idx_waw_page_and_version"

    rename_column :wiki_approval_workflows, :wiki_page_id, :page_id
    rename_column :wiki_approval_workflows, :wiki_version_id, :version

    add_column :wiki_approval_workflows, :revision, :integer

    add_index :wiki_approval_workflows, [:page_id, :version], unique: true, name: "idx_waw_page_and_version"

    add_foreign_key :wiki_approval_workflows, :wiki_pages, column: :page_id
  end

  def down
    remove_foreign_key :wiki_approval_workflows, :wiki_pages

    remove_index :wiki_approval_workflows, name: "idx_waw_page_and_version"

    rename_column :wiki_approval_workflows, :page_id, :wiki_page_id
    rename_column :wiki_approval_workflows, :version, :wiki_version_id

    remove_column :wiki_approval_workflows, :revision

    add_index :wiki_approval_workflows, [:wiki_page_id, :wiki_version_id], unique: true, name: "idx_waw_page_and_version"

    add_foreign_key :wiki_approval_workflows, :wiki_pages, column: :wiki_page_id
  end
end
