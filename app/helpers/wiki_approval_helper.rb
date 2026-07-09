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

  def wiki_approval_users(approval, starter: false, step: nil, note: false,
                          userimage: false, status: false, mouseover: false,
                          userlink: false, approved: false)
    return ''.html_safe unless approval

    items = []

    if starter && approval.author
      entry = approval_user_entry(
        approval.author,
        label: l(:label_wiki_approval_starter),
        updated_at: approval.updated_at,
        userimage: userimage, userlink: userlink,
        mouseover: mouseover, status: status
      )
      note_html = note && approval.note.present? ? approval_note(approval.note, userimage: userimage) : ''.html_safe
      items << content_tag(:li, entry + note_html)
    end

    steps = approval.approval_steps
    steps = steps.select { |s| s.step.to_i == step.to_i } if step.present?
    steps = steps.select(&:step_status_approved?) if approved

    # early return
    return ''.html_safe if !starter && steps.empty?

    steps.each do |approval_step|
      entry = approval_user_entry(
        approval_step.principal,
        label: l("wiki_approval_workflow_steps.step_status.#{approval_step.step_status}"),
        updated_at: approval_step.updated_at,
        userimage: userimage, userlink: userlink,
        mouseover: mouseover, status: status,
        step: approval_step.step,
        step_type: approval_step.step_type
      )
      note_html = note && approval_step.note.present? ? approval_note(approval_step.note, userimage: userimage) : ''.html_safe
      items << content_tag(:li, entry + note_html)
    end

    content_tag(:div, content_tag(:ul, safe_join(items)), class: 'approval')
  end

  def approval_user_entry(user, label:, updated_at:, userimage:, userlink:, mouseover:, status:, step: nil, step_type: nil)
    return ''.html_safe unless user

    content_tag(:div, class: 'rwa-user') do
      html = ''.html_safe

      html << avatar(user, size: 22, title: user.name) if userimage

      name = if userlink
               user.is_a?(Group) ? link_to(user.name, group_path(user)) : link_to_user(user)
             else
               user.name
             end
      html << content_tag(:div, name)

      if status
        title = if mouseover
                  [
                    step && "#{l(:label_wiki_approval_step)} #{step}",
                    step_type && I18n.t("wiki_approval_#{step_type}", default: ''),
                    updated_at && "#{l(:label_ago)} #{time_ago_in_words(updated_at)}"
                  ].compact.join(' | ')
                end
        html << content_tag(:div, label, class: 'rwa-status', title: title)
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

  def wiki_approval_column_value(record, waw, waw_approved, project, column)
    case column.name
    when :project
      project.name
    when :title
      path = project_wiki_page_path(project, record.title)
      link_to(record.title, path)
    when :created_on
      format_time(record.created_on)
    when :protected
      record.protected? ? l(:general_text_yes) : l(:general_text_no)
    when :page_parent
      if record.parent
        path = project_wiki_page_path(project, record.parent.title)
        link_to(record.parent.title, path)
      else
        '–'
      end
    when :content_comments
      record.content&.comments
    when :content_updated_on
      format_time(record.content&.updated_on)
    when :content_version
      path = project_wiki_page_path(project, record.title, version: record.content.version)
      link_to(record.content.version, path)
    when :approved_revision
      waw_approved&.revision
    when :workflow_status
      waw&.status
    when :workflow_updated_at
      format_time(waw&.updated_at)
    when :workflow_users
      wiki_approval_users(waw, note: true, status: true)
    when :workflow_author
      wiki_approval_users(waw, starter: true, note: true, step: 0)
    else
      column.value(record)
    end
  end

  def grouped_wiki_approval_list(records, query, counts_by_group, &)
    previous_group = false
    records.each do |record|
      project      = record.wiki&.project
      waw          = record.current_wiki_aw
      waw_approved = record.approved_wiki_aw

      group_name  = nil
      group_count = nil

      if query.grouped?
        group = begin
          case query.group_by_column.name
          when :project
            project&.name
          when :page_parent
            record.parent&.title
          when :protected
            record.protected? ? l(:general_text_yes) : l(:general_text_no)
          when :workflow_status
            waw&.status
          else
            query.group_by_column.value(record)
          end
        rescue
          nil
        end

        if group != previous_group
          group_name  = group.blank? ? l(:label_none) : group.to_s
          group_count =
            case query.group_by_column.name
            when :protected
              counts_by_group&.dig(record.protected)
            when :workflow_status
              counts_by_group&.dig(waw&.status_before_type_cast)
            else
              counts_by_group&.dig(group)
            end

          previous_group = group
        end
      end
      yield record, project, waw, waw_approved, group_name, group_count
    end
  end

  def wiki_approval_group_link(group_name, column, first_record)
    return l(:label_none) if group_name.blank?

    waw          = first_record.current_wiki_aw
    waw_approved = first_record.approved_wiki_aw
    project      = first_record.wiki&.project

    case column.name
    when :project
      link_to(project.name, project_wiki_index_path(project))
    when :page_parent
      wiki_approval_column_value(first_record, waw, waw_approved, project, column)
    else
      group_name
    end
  end
end
