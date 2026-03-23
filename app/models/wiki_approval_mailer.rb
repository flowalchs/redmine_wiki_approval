# frozen_string_literal: true

require 'mailer'

# Mailer
class WikiApprovalMailer < Mailer
  layout 'mailer'

  def self.deliver_wiki_approval_state(approval, status, wiki_page, actor)
    return unless Setting.notified_events.include?('wiki_approval_notifications')

    project = wiki_page.project

    # project members & watchers
    membership_by_user_id = project.members.active.includes(:user).index_by { |m| m.user_id }
    watcher_user_ids = wiki_page.watchers.pluck(:user_id).to_set

    # author current version
    current_author_id  = wiki_page.content&.author_id

    # Approval Principals in Steps, groups to userids
    approval_principal_ids = approval.approval_steps
      .where.not(status: WikiApprovalWorkflowSteps.statuses[:unstarted])
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

    approval_principal_ids   = (approval_principal_ids | [approval&.author_id]).compact

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
          approval_principal_ids.include?(u.id) ||
          current_author_id == u.id
          acc << u
        end

      when 'none'
        next

      else
        acc << u if watcher_user_ids.include?(u.id) ||
          approval_principal_ids.include?(u.id) ||
          current_author_id == u.id

      end
    end

    recipients.uniq

    recipients.each do |user|
      wiki_approval(user, approval, status, wiki_page, actor, I18n.t("field_status", default: "status")).deliver_later
    end
  end

  def self.deliver_wiki_approval_step(approval, wiki_page, actor, step)
    return unless Setting.notified_events.include?('wiki_approval_notifications')

    approval_principal_ids = approval.approval_steps
      .where(status: WikiApprovalWorkflowSteps.statuses[:pending])
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
    ver_num = approval.wiki_version_id
    project = wiki_page.project
    last_public = WikiApprovalWorkflow.latest_public_from_version(approval.wiki_page_id, approval.wiki_version_id)

    redmine_headers 'Project' => project,
                    'Wiki-Page-Id' => wiki_page.id,
                    'Wiki-Version' => approval.wiki_version_id,
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
end
