# frozen_string_literal: true

module WikiApprovalHelper
  def wiki_approval_badge(status)
    case status
    when 'draft', 'canceled'
      'badge-status-locked'
    when 'pending'
      'badge-status-open'
    when 'rejected'
      'badge-private'
    when 'released', 'published'
      'badge-status-closed'
    end
  end

  def render_workflow_fields(api, workflow)
    return unless workflow

    api.id workflow.id
    api.version workflow.version
    api.revision workflow.revision
    api.author(id: workflow.author_id, name: workflow.author&.name)
    api.status workflow.status
    api.note workflow.note unless workflow.note.nil?
    api.created_at workflow.created_at
    api.updated_at workflow.updated_at
    api.array :wiki_approval_workflow_steps do
      workflow.approval_steps.each do |s|
        api.step do
          api.id          s.id
          api.step        s.step
          api.step_type   s.step_type
          api.step_status s.step_status
          api.principal(id: s.principal_id, type: s.principal_type, name: s.principal.name)
          api.note        s.note if s.note.present?
          api.created_at  s.created_at
          api.updated_at  s.updated_at
        end
      end
    end
  end

  def render_page_fields(api, page)
    return unless page

    api.id page.id
    api.wiki_id page.wiki_id
    api.title page.title
    api.created_on page.created_on
    api.protected page.protected
    api.parent_id page.parent_id unless page.parent_id?
    if page.parent
      api.parent :title => page.parent.title
    end
  end
end
