# frozen_string_literal: true

module WikiHistoryOverride
  Deface::Override.new(
    virtual_path: 'wiki/history',
    name: 'wiki_approval_history_th_after_comments',
    insert_after: "th:contains('field_comments')",
    partial: 'wiki/history_approval_th',
    original: 'acb043691507cc2da0728a2701d70b9fbad5a804'
  )

  Deface::Override.new(
    virtual_path: 'wiki/history',
    name: 'wiki_approval_history_td_after_comments',
    insert_after: "td.comments",
    partial: 'wiki/history_approval_td',
    original: '1628da1ddd7d53c95651b69e939dbad880015e75'
  )
end
