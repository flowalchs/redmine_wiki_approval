require File.expand_path('../test_helper', __dir__)

class WikiApprovalMailNotificationsTest < WikiApproval::Test::UnitCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  def setup
    super
    ActiveJob::Base.queue_adapter     = :test
    ActionMailer::Base.delivery_method = :test
    ActionMailer::Base.perform_deliveries = true
    ActionMailer::Base.deliveries.clear

    Setting.notified_events = Redmine::Notifiable.all.collect(&:name)
    Setting.bcc_recipients = '0' if Rails::VERSION::MAJOR == 5 # redmine 4
    User.current = nil

    @jsmith.mail_notification = 'only_my_events'
    @jsmith.save!
    @dlopper.mail_notification = 'only_my_events'
    @dlopper.save!
    @rhill.mail_notification = 'only_my_events'
    @rhill.save!
  end

  def test_status_mail
    approval = WikiApprovalWorkflow.find_by(id: 1)

    perform_enqueued_jobs do
      WikiApprovalMailer.deliver_wiki_approval_state(approval, approval.status, approval.wiki_page, approval.author)
    end

    deliveries = ActionMailer::Base.deliveries
    assert_equal 1, deliveries.size

    to_set = deliveries.flat_map { |m| Array(m.to) }.to_set
    expected_set = Set['jsmith@somenet.foo']
    assert_equal expected_set, to_set

    subjects = deliveries.map(&:subject)
    assert subjects.all? { |s| s.include?('Wiki approval workflow') }

    mail = deliveries.last
    assert_mail_body_match 'Released', mail
  end

  def test_status_mail_notify_all
    @dlopper.mail_notification = 'all'
    @dlopper.save!
    approval = WikiApprovalWorkflow.find_by(id: 1)

    perform_enqueued_jobs do
      WikiApprovalMailer.deliver_wiki_approval_state(approval, approval.status, approval.wiki_page, approval.author)
    end

    deliveries = ActionMailer::Base.deliveries
    assert_equal 2, deliveries.size

    to_set = deliveries.flat_map { |m| Array(m.to) }.to_set
    expected_set = Set['jsmith@somenet.foo', 'dlopper@somenet.foo']
    assert_equal expected_set, to_set
  end

  def test_status_mail_pending
    approval = WikiApprovalWorkflow.find_by(id: 2)

    perform_enqueued_jobs do
      WikiApprovalMailer.deliver_wiki_approval_state(approval, approval.status, approval.wiki_page, approval.author)
    end

    deliveries = ActionMailer::Base.deliveries
    assert_equal 2, deliveries.size

    to_set = deliveries.flat_map { |m| Array(m.to) }.to_set
    expected_set = Set['jsmith@somenet.foo', 'dlopper@somenet.foo']
    assert_equal expected_set, to_set

    subjects = deliveries.map(&:subject)
    assert subjects.all? { |s| s.include?('Wiki approval workflow') }

    mail = deliveries.last
    assert_mail_body_match 'pending', mail
  end

  def test_status_mail_watcher
    approval = WikiApprovalWorkflow.find_by(id: 2)

    @page  = WikiPage.find(11)
    @page.add_watcher(@rhill)

    perform_enqueued_jobs do
      WikiApprovalMailer.deliver_wiki_approval_state(approval, approval.status, approval.wiki_page, approval.author)
    end

    deliveries = ActionMailer::Base.deliveries
    assert_equal 3, deliveries.size

    to_set = deliveries.flat_map { |m| Array(m.to) }.to_set
    expected_set = Set['jsmith@somenet.foo', 'dlopper@somenet.foo', "rhill@somenet.foo"]
    assert_equal expected_set, to_set
  end

  def test_status_mail_step1_two
    Member.create!(project: @project, principal: @rhill, roles: [@developer_role])
    approval = WikiApprovalWorkflow.find_by(id: 2)

    step = approval.approval_steps.for_principal(@rhill).find_or_initialize_by(step: 1)
    step.step_status = :pending
    step.save!

    perform_enqueued_jobs do
      WikiApprovalMailer.deliver_wiki_approval_state(approval, approval.status, approval.wiki_page, approval.author)
    end

    deliveries = ActionMailer::Base.deliveries
    assert_equal 3, deliveries.size

    to_set = deliveries.flat_map { |m| Array(m.to) }.to_set
    expected_set = Set['jsmith@somenet.foo', 'dlopper@somenet.foo', "rhill@somenet.foo"]
    assert_equal expected_set, to_set
  end

  def test_status_mail_step2_wait
    Member.create!(project: @project, principal: @rhill, roles: [@developer_role])
    approval = WikiApprovalWorkflow.find_by(id: 2)

    step = approval.approval_steps.for_principal(@rhill).find_or_initialize_by(step: 2)
    step.step_status = :unstarted
    step.save!

    perform_enqueued_jobs do
      WikiApprovalMailer.deliver_wiki_approval_state(approval, approval.status, approval.wiki_page, approval.author)
    end

    deliveries = ActionMailer::Base.deliveries
    assert_equal 2, deliveries.size

    to_set = deliveries.flat_map { |m| Array(m.to) }.to_set
    expected_set = Set['jsmith@somenet.foo', 'dlopper@somenet.foo']
    assert_equal expected_set, to_set
  end

  def test_status_mail_approved
    approval = WikiApprovalWorkflow.find_by(id: 2)

    perform_enqueued_jobs do
      step = approval.approval_steps.find_or_initialize_by(step: 1)
      step.step_status = :approved
      step.save!
    end

    deliveries = ActionMailer::Base.deliveries
    assert_equal 2, deliveries.size

    to_set = deliveries.flat_map { |m| Array(m.to) }.to_set
    expected_set = Set['jsmith@somenet.foo', 'dlopper@somenet.foo']
    assert_equal expected_set, to_set

    mail = deliveries.last
    assert_mail_body_match 'Released', mail
  end

  def test_step_mail_next
    Member.create!(project: @project, principal: @rhill, roles: [@developer_role])
    approval = WikiApprovalWorkflow.find_by(id: 2)

    step1 = approval.approval_steps.for_principal(@rhill).find_or_initialize_by(step: 2)
    step1.step_status = :unstarted
    step1.step_type = 1
    step1.save!

    perform_enqueued_jobs do
      step2 = approval.approval_steps.for_principal(@dlopper).find_or_initialize_by(step: 1)
      step2.step_status = :approved
      step2.step_type = 1
      step2.save!
    end

    deliveries = ActionMailer::Base.deliveries
    assert_equal 1, deliveries.size

    to_set = deliveries.flat_map { |m| Array(m.to) }.to_set
    expected_set = Set["rhill@somenet.foo"]
    assert_equal expected_set, to_set

    mail = deliveries.last
    assert_mail_body_match 'In approval', mail
    assert_mail_body_match 'Approved', mail
  end

  def test_status_mail_notify_selected_project
    Member.create!(project: @project, principal: @rhill, roles: [@developer_role])
    # 1. Globaler Schalter (hast du schon)
    @rhill.update!(mail_notification: 'selected')

    # 2. Die "Liste" pflegen (das ist die Member-Tabelle)
    member = Member.where(user_id: @rhill.id, project_id: @project.id).first
    member.update!(mail_notification: true)

    approval = WikiApprovalWorkflow.find_by(id: 1)

    perform_enqueued_jobs do
      WikiApprovalMailer.deliver_wiki_approval_state(approval, approval.status, approval.wiki_page, approval.author)
    end

    deliveries = ActionMailer::Base.deliveries
    assert_equal 2, deliveries.size

    to_set = deliveries.flat_map { |m| Array(m.to) }.to_set
    expected_set = Set['jsmith@somenet.foo', 'rhill@somenet.foo']
    assert_equal expected_set, to_set
  end

  def test_step_mail_next_group
    user = User.find(9)
    @group.users << user
    Member.create!(project: @project, principal: @group, roles: [@developer_role])
    approval = WikiApprovalWorkflow.find_by(id: 2)

    step1 = approval.approval_steps.for_principal(@group).find_or_initialize_by(step: 2)
    step1.step_status = :unstarted
    step1.step_type = 1
    step1.save!

    perform_enqueued_jobs do
      step2 = approval.approval_steps.for_principal(@dlopper).find_or_initialize_by(step: 1)
      step2.step_status = :approved
      step2.step_type = 1
      step2.save!
    end

    deliveries = ActionMailer::Base.deliveries
    assert_equal 2, deliveries.size

    to_set = deliveries.flat_map { |m| Array(m.to) }.to_set
    expected_set = Set["miscuser8@foo.bar", "miscuser9@foo.bar"]
    assert_equal expected_set, to_set
  end

  def test_status_mail_step1_two_group
    user = User.find(9)
    @group.users << user
    Member.create!(project: @project, principal: @group, roles: [@developer_role])
    approval = WikiApprovalWorkflow.find_by(id: 2)

    step = approval.approval_steps.for_principal(@group).find_or_initialize_by(step: 1)
    step.step_status = :pending
    step.save!

    perform_enqueued_jobs do
      WikiApprovalMailer.deliver_wiki_approval_state(approval, approval.status, approval.wiki_page, approval.author)
    end

    deliveries = ActionMailer::Base.deliveries
    assert_equal 4, deliveries.size

    to_set = deliveries.flat_map { |m| Array(m.to) }.to_set
    expected_set = Set["miscuser8@foo.bar", "miscuser9@foo.bar", "jsmith@somenet.foo", "dlopper@somenet.foo"]
    assert_equal expected_set, to_set
  end
end
