# frozen_string_literal: true

class FillRevisionWikiApprovalWorkflow < ActiveRecord::Migration[5.2]
  # Lokales Model für die Migration (nur DB, keine Redmine-Abhängigkeiten)
  class Waw < ActiveRecord::Base
    self.table_name = "wiki_approval_workflows"
  end

  def up
    say_with_time "Setting revision numbers for published/released workflows" do
      # statuses[:published]  => 60
      # statuses[:released]   => 70
      approved_statuses = [60, 70]

      Waw.where(status: approved_statuses)
         .order(:page_id, :created_at)
         .group_by(&:page_id)
         .each_value do |workflows|
        rev = 1
        workflows.each do |w|
          w.update_column(:revision, rev)
          rev += 1
        end
      end
    end
  end

  def down
    Waw.update_all(revision: nil)
  end
end
