# frozen_string_literal: true

module WikiEditOverride
  Deface::Override.new(
    virtual_path: 'wiki/edit',
    name: 'wiki_approval_insert_after_comments',
    insert_after: "p:has(erb[loud]:contains(':field_comments'))",
    partial: 'wiki/edit_form',
    original: '3b42b3153896e651b770aed6d379d11acbcbc0f9'
  )

  Deface::Override.new(
    virtual_path: 'wiki/edit',
    name: 'wiki_approval_insert_after_save_button',
    insert_after: "erb[loud]:contains('submit_tag l(:button_save)')",
    partial: 'wiki/edit_form_button',
    original: 'e95f8add55a16c2672c3f01f87576c8da02492ee'
  )
end
