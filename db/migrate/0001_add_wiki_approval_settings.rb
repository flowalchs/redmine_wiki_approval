# frozen_string_literal: true

class AddWikiApprovalSettings < ActiveRecord::Migration[5.2]
  def self.up
    create_table :wiki_approval_settings do |t|
      t.references :project, null: false, index: { name: 'index_wiki_approval_settings_project' }
      t.text :json_data
      t.timestamps null: false
    end
  end

  def self.down
    drop_table :wiki_approval_settings
  end
end
