# frozen_string_literal: true

class AddWikiDraftComments < ActiveRecord::Migration[5.2]
  def up
    add_column :wiki_approval_draft, :comments, :string, :limit => 255, :default => ""
  end

  def down
    remove_column :wiki_approval_draft, :comments
  end
end
