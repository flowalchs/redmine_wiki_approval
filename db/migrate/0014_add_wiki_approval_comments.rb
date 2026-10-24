# frozen_string_literal: true

class AddWikiApprovalComments < ActiveRecord::Migration[5.2]
  def self.up
    create_table :wiki_approval_comments do |t|
      t.integer :page_id, null: false, index: { name: 'idx_wac_page_id' }
      t.integer :parent_id, index: { name: 'idx_wac_parent_id' }
      t.integer :author_id, null: false, index: { name: 'idx_wac_author_id' }
      # running number per page, starting at 1
      t.integer :number
      t.text :text, null: false
      # inline anchor (TextQuoteSelector), quote nil = page comment
      t.text :quote
      t.string :prefix, limit: 255
      t.string :suffix, limit: 255
      # version where the thread was started
      t.integer :version
      t.integer :status, null: false, default: 0
      t.integer :resolved_version
      t.integer :resolved_by_id
      t.datetime :resolved_at
      t.timestamps null: false
    end
    add_index :wiki_approval_comments, [:page_id, :number], name: 'idx_wac_page_number'
    add_foreign_key(
      :wiki_approval_comments,
      :wiki_pages,
      column: :page_id
    )

    # history of resolve / reopen (activity and mails)
    create_table :wiki_approval_comment_statuses do |t|
      t.integer :comment_id, null: false, index: { name: 'idx_wacs_comment_id' }
      t.integer :author_id, null: false
      t.integer :status, null: false
      t.integer :version
      t.datetime :created_at, null: false
    end
  end

  def self.down
    drop_table :wiki_approval_comment_statuses
    drop_table :wiki_approval_comments
  end
end
