class UpdateCurrentPageId < ActiveRecord::Migration[5.2]
  class Waw < ActiveRecord::Base
    self.table_name = "wiki_approval_workflows"
  end

  def up
    say_with_time "Updating current_page_id for newest versions" do
      last_page_id = nil
      relevant_ids = []

      Waw.select(:id, :page_id)
         .order(page_id: :asc, version: :desc, id: :desc)
         .each do |w|
        if w.page_id != last_page_id
          relevant_ids << w.id
          last_page_id = w.page_id
        end
      end

      if relevant_ids.any?
        Waw.where(id: relevant_ids).update_all("current_page_id = page_id")
      end
    end
  end

  def down
    Waw.update_all(current_page_id: nil)
  end
end
