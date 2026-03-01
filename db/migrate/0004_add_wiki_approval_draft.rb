# frozen_string_literal: true

class AddWikiApprovalDraft < ActiveRecord::Migration[5.2]
  def self.up
    create_table :wiki_approval_draft do |t|
      t.integer :wiki_page_id, null: false, index: { name: 'idx_wad_page_id', unique: true }
      t.integer :author_id, null: false, index: { name: 'idx_wad_author_id' }
      t.text :text
      t.timestamps null: false
    end
    add_foreign_key(
      :wiki_approval_draft,
      :wiki_pages,
      column: :wiki_page_id
    )
  end

  def self.down
    drop_table :wiki_approval_draft
  end
end
