# frozen_string_literal: true

require 'mailer'

# Mailer
class WikiApprovalMailer < Mailer
  layout 'mailer'

  helper :wiki_approval

  def self.deliver_wiki_approval_state(approval, status, wiki_page, actor)
    return unless Setting.notified_events.include?('wiki_approval_notifications')

    approval_principal_ids = (approval_principal_ids(approval) | [approval&.author_id]).compact

    wiki_page_recipients(wiki_page, actor, approval_principal_ids).each do |user|
      wiki_approval(user, approval, status, wiki_page, actor, I18n.t("field_status", default: "status")).deliver_later
    end
  end

  # comment added (:added), resolved (:resolved) or reopened (:reopened),
  # to the same users as the approval mails plus the users of the thread
  def self.deliver_wiki_comment(comment, event, actor)
    notifiable = event == :added ? 'wiki_comment_added' : 'wiki_comment_status_changed'
    return unless Setting.notified_events.include?(notifiable)

    wiki_page = comment.wiki_page
    project = wiki_page.project
    thread = comment.parent || comment
    involved_ids = [thread.author_id] + thread.replies.pluck(:author_id)
    approval = WikiApprovalWorkflow.where(page_id: wiki_page.id).order(:id).last
    involved_ids |= (approval_principal_ids(approval) | [approval.author_id]) if approval

    wiki_page_recipients(wiki_page, actor, involved_ids.compact.uniq).each do |user|
      next unless user.allowed_to?(:wiki_comments_view, project)

      wiki_comment(user, comment, event, actor).deliver_later
    end
  end

  # users of the approval steps (groups as their users), unstarted steps excluded
  def self.approval_principal_ids(approval)
    return [] unless approval

    approval.approval_steps
      .where.not(step_status: WikiApprovalWorkflowStep.step_statuses[:unstarted])
      .each_with_object([]) do |step, acc|
        principal = step.principal
        case principal
        when User
          acc << principal.id
        when Group
          acc.concat(principal.user_ids)
        end
      end
      .uniq
  end

  # project members, watchers and involved users, filtered by their mail notification settings
  def self.wiki_page_recipients(wiki_page, actor, involved_ids)
    project = wiki_page.project

    # project members & watchers
    membership_by_user_id = project.members.active.includes(:user).index_by { |m| m.user_id }
    watcher_user_ids = wiki_page.watchers.pluck(:user_id).to_set

    # author current version
    current_author_id  = wiki_page.content&.author_id

    # Candidates: Project members + Watcher + Content.notified_users (if available)
    member_users = membership_by_user_id.values.map(&:user).compact
    extra_users  = (wiki_page.content&.notified_users || []) | User.where(id: watcher_user_ids.to_a).to_a
    candidates   = (member_users | extra_users).uniq

    # ---- Filter by user preference ----
    recipients = candidates.each_with_object([]) do |u, acc|
      # Only active users with email
      next unless u&.active? && u.mail.present?

      # no_self_notified: Possibly exclude the actor themselves
      next if actor && u.id == actor.id && u.pref&.no_self_notified

      case u.mail_notification
      when 'all'
        acc << u

      when 'selected'
        if ((m = membership_by_user_id[u.id]) && m.mail_notification?) ||
          watcher_user_ids.include?(u.id) ||
          involved_ids.include?(u.id) ||
          current_author_id == u.id
          acc << u
        end

      when 'none'
        next

      else
        acc << u if watcher_user_ids.include?(u.id) ||
          involved_ids.include?(u.id) ||
          current_author_id == u.id

      end
    end

    recipients.uniq
  end

  def self.deliver_wiki_approval_step(approval, wiki_page, actor, step)
    return unless Setting.notified_events.include?('wiki_approval_notifications')

    approval_principal_ids = approval.approval_steps
      .where(step_status: WikiApprovalWorkflowStep.step_statuses[:pending])
      .each_with_object([]) do |step, acc|
        principal = step.principal
        case principal
        when User
          acc << principal.id
        when Group
          acc.concat(principal.user_ids)
        end
      end
      .uniq

    recipients = User
      .where(id: approval_principal_ids, type: 'User', status: User::STATUS_ACTIVE)
      .where.not(mail_notification: 'none')
      .includes(:email_address)
      .select { |u| u.mail.present? }

    recipients.each do |user|
      wiki_approval(user, approval, approval.status, wiki_page, actor, "#{I18n.t(:label_wiki_approval_step, default: 'Step')} #{step}").deliver_later
    end
  end

  def wiki_approval(user, approval, status, wiki_page, actor, type)
    ver_num = approval.version
    project = wiki_page.project
    last_public = WikiApprovalWorkflow.latest_public_from_version(approval.page_id, approval.version)

    redmine_headers 'Project' => project,
                    'Wiki-Page-Id' => wiki_page.id,
                    'Wiki-Version' => approval.version,
                    'Approval-State'=> status

    subject = "[#{project.name} - #{wiki_page.title}] (#{I18n.t("wiki_approval_workflow.status.#{status}", default: status)}) " \
              "#{I18n.t("label_wiki_approval_notifications", default: "approval")}"

    @type = type
    @actor = actor
    @approval = approval
    @wiki_page = wiki_page
    @wiki_page_title = "#{wiki_page.title} (##{ver_num})"
    @wiki_page_url = url_for(:controller => 'wiki', :action => 'show', :project_id => project, :id => wiki_page.title, :version => ver_num)
    @diff_url =      url_for(:controller => 'wiki', :action => 'diff', :project_id => project, :id => wiki_page.title, :version => ver_num, :version_from => last_public)

    mail :to => user.mail,
         :subject => subject
  end

  def wiki_comment(user, comment, event, actor)
    wiki_page = comment.wiki_page
    project = wiki_page.project

    redmine_headers 'Project' => project,
                    'Wiki-Page-Id' => wiki_page.id,
                    'Wiki-Comment' => comment.number

    @event = event
    @actor = actor
    @comment = comment
    @thread = comment.parent || comment
    @wiki_page = wiki_page
    @comment_url = url_for(controller: 'wiki', action: 'show', project_id: project, id: wiki_page.title,
                           anchor: "comment-#{comment.number}")

    subject = "[#{project.name} - #{wiki_page.title}] #{I18n.t("label_wiki_comment_#{event}")} ##{comment.number}"
    mail to: user.mail, subject: subject
  end
end
