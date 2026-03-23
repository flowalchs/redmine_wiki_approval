# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class WikiApprovalMailControllerTest < WikiApproval::Test::ControllerCase
  tests WikiApprovalController
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  def setup
    super
    set_session_user(@jsmith)
    @page = WikiPage.find_by(id: 11)

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

  test "should send step mail for start_approval which previously had the status pending" do
    perform_enqueued_jobs do
      post :start_approval, params: {
        project_id: @project.id,
        title: @page.title,
        version: @page.content.version,
        steps: {
          "1" => [
            { "principal_id" => @dlopper.id.to_s },
            { "principal_id" => @rhill.id.to_s }
          ],
          "2" => [
            { "principal_id" => @jsmith.id.to_s },
            { "principal_id" => @group.id.to_s }
          ]
        },
        steps_typ: { "1" => "or", "2" => "and" },
        note: "multiple steps"
      }
    end

    deliveries = ActionMailer::Base.deliveries
    assert_equal 2, deliveries.size

    to_set = deliveries.flat_map { |m| Array(m.to) }.to_set
    expected_set = Set["dlopper@somenet.foo", "rhill@somenet.foo"]
    assert_equal expected_set, to_set

    mail = deliveries.last

    # just step1
    assert_mail_body_match /Step 1 was updated by John Smith/, mail
    assert_mail_body_match /Step 1/, mail
    assert_mail_body_match /Dave Lopper.*?Status:\s*In approval/m, mail
    assert_mail_body_match /Robert Hill.*?Status:\s*In approval/m, mail
    assert_mail_body_match /Step 2/, mail
    assert_mail_body_match /John Smith.*?Status:\s*Planned/m, mail
    assert_mail_body_match /A Team.*?Status:\s*Planned/m, mail
  end

  test "should send step mail forwar_approval to step users" do
    set_session_user(@dlopper)

    perform_enqueued_jobs do
      post :forward_approval, params: {
        project_id: @project.id,
        title: @page.title,
        version: @page.content.version,
        step_id: 2,
        note: "forward to other user",
        principal_id: @rhill.id
      }
    end

    deliveries = ActionMailer::Base.deliveries
    assert_equal 1, deliveries.size

    to_set = deliveries.flat_map { |m| Array(m.to) }.to_set
    expected_set = Set["rhill@somenet.foo"]
    assert_equal expected_set, to_set

    mail = deliveries.last

    # just step1
    assert_mail_body_match /Step 1 was updated by Dave Lopper/, mail
    assert_mail_body_match /Step 1/, mail
    assert_mail_body_match /Robert Hill.*?Status:\s*In approval/m, mail
    assert_mail_body_no_match /Step 2/, mail
  end

  test "should send step mail for start_approval not to user notification none" do
    @rhill.mail_notification = 'none'
    @rhill.save!

    perform_enqueued_jobs do
      post :start_approval, params: {
        project_id: @project.id,
        title: @page.title,
        version: @page.content.version,
        steps: {
          "1" => [
            { "principal_id" => @dlopper.id.to_s },
            { "principal_id" => @rhill.id.to_s }
          ],
          "2" => [
            { "principal_id" => @jsmith.id.to_s },
            { "principal_id" => @group.id.to_s }
          ]
        },
        steps_typ: { "1" => "or", "2" => "and" },
        note: "multiple steps"
      }
    end

    deliveries = ActionMailer::Base.deliveries
    assert_equal 1, deliveries.size

    to_set = deliveries.flat_map { |m| Array(m.to) }.to_set
    expected_set = Set["dlopper@somenet.foo"]
    assert_equal expected_set, to_set
  end
end
