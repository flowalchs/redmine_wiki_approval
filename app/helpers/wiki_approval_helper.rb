# frozen_string_literal: true

module WikiApprovalHelper
  def wiki_approval_badge(status, style: nil)
    return '' if status.blank?

    css_class =
      case status
      when 'draft', 'canceled'
        'badge-status-locked'
      when 'pending'
        'badge-status-open'
      when 'rejected'
        'badge-private'
      when 'released', 'published'
        'badge-status-closed'
      else
        ''
      end
    options = {
      class: "badge #{css_class}".strip,
      style: style.presence || 'bottom: 0px'
    }
    content_tag(
      :span,
      l("wiki_approval_workflow.status.#{status}"),
      options
    )
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

  def wiki_approval_users(approval,
                          starter: false,
                          step: nil,
                          note: false,
                          userimage: false,
                          status: false,
                          mouseover: false,
                          userlink: false,
                          approved: false)
    return '' unless approval

    items = []

    # === Starter ===
    if starter && approval.author
      items << content_tag(:li) do
        approval_user_entry(
          approval.author,
          label: l(:label_wiki_approval_starter),
          updated_at: approval.updated_at,
          userimage: userimage,
          userlink: userlink,
          mouseover: mouseover,
          status: status
        ) +
        (note && approval.note.present? ? approval_note(approval.note, userimage: userimage) : ''.html_safe)
      end
    end

    # === Steps ===
    steps = approval.approval_steps.order(:step)
    steps = steps.where(step: step) if step.present?
    steps = steps.where(step_status: :approved) if approved

    steps.each do |approval_step|
      items << content_tag(:li) do
        approval_user_entry(
          approval_step.principal,
          label: l("wiki_approval_workflow_steps.step_status.#{approval_step.step_status}"),
          updated_at: approval_step.updated_at,
          userimage: userimage,
          userlink: userlink,
          mouseover: mouseover,
          status: status,
          step: approval_step.step,
          step_type: approval_step.step_type
        ) +
        (note && approval_step.note.present? ? approval_note(approval_step.note, userimage: userimage) : ''.html_safe)
      end
    end

    content_tag :div, class: 'approval' do
      content_tag :ul, safe_join(items)
    end
  end

  def approval_user_entry(user, label:, updated_at:, userimage:, userlink:, mouseover:, status:, step: nil, step_type: nil)
    content_tag(:div, class: 'rwa-user') do
      html = ''.html_safe

      if userimage && user
        html << avatar(user, size: 22, title: user.name)
      end

      if user
        name = if userlink
                 user.is_a?(Group) ? link_to(user.name, group_path(user)) : link_to_user(user)
               else
                 user.name
               end
        html << content_tag(:div, name)
      end

      if status
        html << content_tag(
          :div,
          label,
          class: 'rwa-status',
          title: if mouseover
                   [step && "#{l(:label_wiki_approval_step)} #{step}",
                    step_type && I18n.t("wiki_approval_#{step_type}", default: '').to_s,
                    updated_at && "#{l(:label_ago)} #{time_ago_in_words(updated_at)}"].compact.join(' | ')
                 else
                   nil
                 end
        )
      end

      html
    end
  end

  def approval_note(text, userimage: false)
    content_tag(:div, text, class: ['rwa-note', userimage && 'rwa-avatar-note'].compact.join(' '), title: l(:field_comments))
  end

  def wiki_approval_time(time, format: nil)
    return '' unless time

    case format
    when :relative
      content_tag(
        :span,
        distance_of_time_in_words(Time.now, time),
        title: format_time(time)
      )
    else
      format_time(time)
    end
  end

  def wiki_approval_status_value(status, format: :text)
    return '' if status.blank?

    status = status.to_s

    case format
    when :text
      l("wiki_approval_workflow.status.#{status}")
    else
      wiki_approval_badge(status)
    end
  end

  def wiki_approval_diff(approval:, project:, page:, view_version_id:)
    return '' unless approval
    return '' unless project && page && view_version_id
    return '' unless User.current.allowed_to?(:view_wiki_edits, project)

    link_to(
      l(:label_diff),
      diff_project_wiki_page_path(
        project_id: project.identifier,
        id: page.title,
        version: view_version_id,
        version_from: WikiApprovalWorkflow.latest_public_from_version(
          page.id,
          view_version_id
        )
      )
    )
  end

  def wiki_approval_sidebar_status_visible?(approval_data)
    return false if @wiki_approval_data.nil?
    return false if @wiki_approval_data[:approval].nil?

    approval_data&.dig(:approval)&.status.to_s.in?(
      Array(approval_data[:setting]&.wiki_sidebar_status).map(&:to_s)
    )
  end
end
