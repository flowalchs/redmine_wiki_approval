# frozen_string_literal: true

module WikiShowOverride
  Deface::Override.new(
    virtual_path: 'wiki/show',
    name: 'overlay-wiki-show-contextual',
    insert_before: "erb[loud]:contains('actions_dropdown')",
    partial: 'wiki/show_contextual',
    original: '4f0fda1abd7add605aab5f2688759dc4cca312f4'
  )

  Deface::Override.new(
    virtual_path: 'wiki/show',
    name: 'overlay-wiki-show-actions-dropdown',
    insert_before: "erb[loud]:contains(\"icon-history\")",
    partial: 'wiki/show_actions_dropdown',
    original: 'fc27fab81025c90f072d63af36b0cc1ee32833ee'
  )

  Deface::Override.new(
    virtual_path: 'wiki/show',
    name: 'surround-wiki-show-content-comments',
    surround: "erb[loud]:contains('wiki/content')",
    partial: 'wiki_approval_comments/show_wrapper'
  )
end
