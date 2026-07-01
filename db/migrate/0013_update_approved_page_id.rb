# frozen_string_literal: true

class UpdateApprovedPageId < ActiveRecord::Migration[5.2]
  class Waw < ActiveRecord::Base
    self.table_name = "wiki_approval_workflows"
    APPROVED_STATUS_VALUES = [60, 70].freeze # published: 60, released: 70
  end

  def up
    say_with_time "Updating approved_page_id for latest published/released versions" do
      last_page_id = nil
      approved_ids = []

      Waw
        .where(status: Waw::APPROVED_STATUS_VALUES)
        .order(page_id: :asc, version: :desc, id: :desc)
        .select(:id, :page_id)
        .each do |w|
          if w.page_id != last_page_id
            approved_ids << w.id
            last_page_id = w.page_id
          end
        end

      if approved_ids.any?
        Waw.where(id: approved_ids).update_all("approved_page_id = page_id")
      end

      say "Updated #{approved_ids.size} rows"
    end
  end

  def down
    Waw.update_all(approved_page_id: nil)
  end
end
