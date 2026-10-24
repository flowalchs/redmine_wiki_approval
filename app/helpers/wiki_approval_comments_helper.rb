# frozen_string_literal: true

module WikiApprovalCommentsHelper
  # data for the wiki show page (panel + sidebar), nil if comments are not visible
  def wiki_comments_context
    return @wiki_comments_context if defined?(@wiki_comments_context)

    @wiki_comments_context =
      if @project && @page&.id && @content && RedmineWikiApproval::Settings.view_comments?(@project)
        { page: @page, project: @project, version: @content.version }
          .merge(WikiApprovalComment.version_data(@page, @content.version, reverse: User.current.wants_comments_in_reverse_order?))
      end
  end

  def render_api_wiki_comment(api, comment)
    api.id comment.id
    api.number comment.number
    api.parent_id comment.parent_id unless comment.parent_id.nil?
    api.author(id: comment.author_id, name: comment.author&.name)
    api.text comment.text
    if comment.thread?
      api.status comment.status
      api.version comment.version
      if comment.inline?
        api.quote comment.quote
        api.prefix comment.prefix
        api.suffix comment.suffix
      end
      if comment.resolved?
        api.resolved_by(id: comment.resolved_by_id, name: comment.resolved_by&.name) if comment.resolved_by_id
        api.resolved_version comment.resolved_version
        api.resolved_at comment.resolved_at
      end
    end
    api.created_at comment.created_at
    api.updated_at comment.updated_at
  end

  # textarea behaviour of the redmine core, like in issue notes:
  # 7.0+ list autofill, tab indent and table paste, 6.1 list autofill, 6.0 none
  def wiki_comment_textarea_data
    if respond_to?(:wiki_textarea_stimulus_attributes)
      wiki_textarea_stimulus_attributes
    elsif respond_to?(:list_autofill_data_attributes)
      list_autofill_data_attributes
    else
      {}
    end
  end

  def wiki_comments_can_add?(project)
    RedmineWikiApproval::Settings.add_comments?(project)
  end

  def wiki_comments_url(page, project, version)
    wiki_approval_comments_path(project_id: project.identifier, title: page.title, version: version)
  end

  def wiki_comment_url(comment, page, project, version)
    wiki_approval_comment_path(project_id: project.identifier, title: page.title, id: comment.id, version: version)
  end

  def wiki_comment_resolve_url(comment, page, project, version)
    wiki_approval_comment_resolve_path(project_id: project.identifier, title: page.title, id: comment.id, version: version)
  end

  def wiki_comment_text(comment, project)
    textilizable(comment, :text, project: project, only_path: true)
  end

  def wiki_comment_version_link(page, project, version)
    return '' unless version

    link_to("#{l(:label_revision)} #{version}",
            project_wiki_page_path(project, page.title, version: version),
            class: 'rwa-comment-version')
  end

  def wiki_comment_resolved_info(comment, page, project)
    return '' unless comment.resolved?

    parts = [l(:label_wiki_comment_resolved_by, user: comment.resolved_by&.name || l(:label_user_anonymous))]
    parts << wiki_comment_version_link(page, project, comment.resolved_version) if comment.resolved_version
    parts << wiki_approval_time(comment.resolved_at, format: :relative) if comment.resolved_at
    safe_join(parts, ' · ')
  end
end
