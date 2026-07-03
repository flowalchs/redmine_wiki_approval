# frozen_string_literal: true

module WikiNewOverride
  Deface::Override.new(
    virtual_path: 'wiki/new',
    name: 'wiki_template_insert_after_title',
    insert_bottom: 'div.box.tabular',
    partial: 'wiki/new_template'
  )
end
