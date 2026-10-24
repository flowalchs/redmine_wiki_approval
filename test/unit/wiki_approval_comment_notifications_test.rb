# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class WikiApprovalCommentNotificationsTest < WikiApproval::Test::UnitCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  def setup
    super
    ActiveJob::Base.queue_adapter = :test
    ActionMailer::Base.delivery_method = :test
    ActionMailer::Base.perform_deliveries = true
    ActionMailer::Base.deliveries.clear

    Setting.notified_events = Redmine::Notifiable.all.collect(&:name)
    User.current = nil
    [@jsmith, @dlopper, @rhill].each do |user|
      user.update!(mail_notification: 'only_my_events')
    end
    [@manager_role, @developer_role].each do |role|
      role.add_permission! :wiki_comments_view
      role.add_permission! :wiki_comments_add
    end
    @page = WikiPage.find(11)
  end

  def recipients
    ActionMailer::Base.deliveries.flat_map { |m| Array(m.to) }.to_set
  end

  test 'reply notifies the thread author' do
    thread = WikiApprovalComment.create!(page_id: @page.id, author: @jsmith, text: 'Thread', version: 2)
    ActionMailer::Base.deliveries.clear

    perform_enqueued_jobs do
      WikiApprovalComment.create!(page_id: @page.id, author: @dlopper, text: 'Reply', parent: thread)
    end

    assert_includes recipients, 'jsmith@somenet.foo'
    mail = ActionMailer::Base.deliveries.find { |m| m.to.include?('jsmith@somenet.foo') }
    assert_match 'Wiki comment added #2', mail.subject
    assert_match 'comment-2', mail.text_part.body.to_s
  end

  test 'resolve and reopen notify and keep a status history' do
    thread = WikiApprovalComment.create!(page_id: @page.id, author: @jsmith, text: 'Thread', version: 2)
    ActionMailer::Base.deliveries.clear

    perform_enqueued_jobs do
      thread.resolve!(@dlopper, 3)
      thread.reopen!(@dlopper, 3)
    end

    assert_equal [1, 0], thread.status_changes.order(:id).pluck(:status)
    subjects = ActionMailer::Base.deliveries.map(&:subject)
    assert(subjects.any? { |s| s.include?('Wiki comment resolved #1') })
    assert(subjects.any? { |s| s.include?('Wiki comment reopened #1') })
  end

  test 'disabled notification sends no mail' do
    Setting.notified_events = Redmine::Notifiable.all.collect(&:name) - %w[wiki_comment_added]

    perform_enqueued_jobs do
      WikiApprovalComment.create!(page_id: @page.id, author: @jsmith, text: 'Thread', version: 2)
    end

    assert_empty ActionMailer::Base.deliveries
  end

  test 'users without view permission get no mail' do
    thread = WikiApprovalComment.create!(page_id: @page.id, author: @jsmith, text: 'Thread', version: 2)
    @manager_role.remove_permission! :wiki_comments_view
    ActionMailer::Base.deliveries.clear

    perform_enqueued_jobs do
      WikiApprovalComment.create!(page_id: @page.id, author: @dlopper, text: 'Reply', parent: thread)
    end

    assert_not_includes recipients, 'jsmith@somenet.foo'
  end
end
