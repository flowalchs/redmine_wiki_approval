# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class WikiApprovalControllerTest < WikiApproval::Test::ControllerCase
  tests WikiApprovalController

  def setup
    super
    set_session_user(@jsmith)
    @page = WikiPage.find_by(title: 'CookBook_documentation')
    @page.content ||= WikiContent.create!(page: @page, text: 'test')
  end

  test "should render start_approval form on GET with permission" do
    get :start_approval, params: { project_id: @project.id, title: @page.title, version: @page.content.version }
    assert_response :success
    assert_match 'Start approval', @response.body
  end

  test "should return 403 on GET without permission" do
    Member.where(user_id: @user.id, project_id: @project.id).destroy_all
    get :start_approval, params: { project_id: @project.id, title: @page.title, version: @page.content.version }
    assert_response :forbidden
  end

  test "should create approval on POST" do
    post :start_approval, params: {
      project_id: @project.id,
      title: @page.title,
      version: @page.content.version,
      steps: { "1" => [{ "principal_id" => @user.id.to_s }] },
      steps_typ: { "1" => "or" },
      note: "Approval started"
    }
    assert_response :redirect
    approval = WikiApprovalWorkflow.find_by(page_id: @page.id)
    assert_not_nil approval
    assert_equal "Approval started", approval.note
    assert_equal 1, approval.approval_steps.count
  end

  test "should reject approval if duplicate users" do
    post :start_approval, params: {
      project_id: @project.id,
      title: @page.title,
      version: @page.content.version,
      steps: {
        "1" => [{ "principal_id" => @user.id.to_s }],
        "2" => [{ "principal_id" => @user.id.to_s }]
      },
      steps_typ: { "1" => "or", "2" => "or" }
    }
    assert_response :success
    assert flash[:error].present?
  end

  test "should grant approval" do
    approval = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :pending,
      author_id: @user.id
    )
    step = approval.approval_steps.for_principal(@user).find_or_initialize_by(step: 1)
    step.step_status = :pending
    step.save!

    post :grant_approval, params: {
      project_id: @project.id,
      title: @page.title,
      version: @page.content.version,
      step_id: step.id,
      note: "Looks good",
      status: "approved"
    }

    assert_response :redirect
    step.reload
    assert_equal 'approved', step.step_status
    assert_equal 'Looks good', step.note
    approval.reload
    assert_equal 'released', approval.status
  end

  test "should forward approval" do
    approval = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :draft,
      author_id: @user.id
    )
    step = approval.approval_steps.for_principal(@user).find_or_initialize_by(step: 1)
    step.step_status = :pending
    step.save!

    post :forward_approval, params: {
      project_id: @project.id,
      title: @page.title,
      version: @page.content.version,
      step_id: step.id,
      note: "forward to group",
      principal_id: @group.id
    }

    assert_response :redirect
    step.reload
    assert_equal 'pending', step.step_status
    assert_equal 'forward to group', step.note
    assert_equal 'Group', step.principal_type
    approval.reload
    assert_equal 'pending', approval.status
  end

  test "should reject forward no comment" do
    approval = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :draft,
      author_id: @user.id
    )
    step = approval.approval_steps.for_principal(@user).find_or_initialize_by(step: 1)
    step.step_status = :pending
    step.save!

    post :forward_approval, params: {
      project_id: @project.id,
      title: @page.title,
      version: @page.content.version,
      step_id: step.id,
      note: "",
      principal_id: @group.id
    }

    assert_response :redirect
    assert_includes flash[:error], I18n.t(:wiki_approval_unable_note)
    step.reload
    assert_equal 'pending', step.step_status
    assert_equal 'User', step.principal_type
    approval.reload
    assert_equal 'pending', approval.status
  end

  test "should reject forward dubilcate user" do
    approval = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :draft,
      author_id: @user.id
    )
    step1 = approval.approval_steps.for_principal(@user).find_or_initialize_by(step: 1)
    step1.step_status = :pending
    step1.save!

    step2 = approval.approval_steps.for_principal(@dlopper).find_or_initialize_by(step: 2)
    step2.step_status = :unstarted
    step2.save!

    post :forward_approval, params: {
      project_id: @project.id,
      title: @page.title,
      version: @page.content.version,
      step_id: step1.id,
      note: "reject dubilcate",
      principal_id: @dlopper.id
    }

    assert_response :redirect
    assert_includes flash[:error], I18n.t(:wiki_approval_unable_start_user)
    step1.reload
    assert_equal 'pending', step1.step_status
    assert_equal @user.id, step1.principal_id
    approval.reload
    assert_equal 'pending', approval.status
  end

  test "should approval multiple steps or and" do
    post :start_approval, params: {
      project_id: @project.id,
      title: @page.title,
      version: @page.content.version,
      steps: {
        "1" => [
          { "principal_id" => @user.id.to_s },
          { "principal_id" => @group.id.to_s }
        ],
        "2" => [
          { "principal_id" => @dlopper.id.to_s },
          { "principal_id" => @rhill.id.to_s }
        ]
      },
      steps_typ: { "1" => "or", "2" => "and" },
      note: "multiple steps"
    }
    assert_response :redirect
    approval = WikiApprovalWorkflow.find_by(page_id: @page.id)
    assert_not_nil approval
    assert_equal 'pending', approval.status
    assert_equal 4, approval.approval_steps.count
    assert_equal 'pending', approval.approval_steps[0].step_status
    assert_equal 'unstarted', approval.approval_steps[2].step_status

    # approved first step
    post :grant_approval, params: {
      project_id: @project.id,
      title: @page.title,
      version: @page.content.version,
      step_id: approval.approval_steps[0].id,
      note: "Looks good",
      status: "approved"
    }
    assert_response :redirect
    approval.reload
    assert_equal 4, approval.approval_steps.count
    assert_equal 'approved', approval.approval_steps[0].step_status
    assert_equal 'canceled', approval.approval_steps[1].step_status
    assert_equal 'pending', approval.approval_steps[2].step_status
    assert_equal 'pending', approval.approval_steps[3].step_status

    # approved step 2 first user
    target_step = approval.approval_steps.find_by(principal_id: @dlopper.id)
    if target_step
      target_step.step_status = :approved
      target_step.save!
    end

    approval.reload
    assert_equal 4, approval.approval_steps.count
    target_step.reload
    assert_equal 'approved', target_step.step_status

    # approved step 2 second user
    target_step = approval.approval_steps.find_by(principal_id: @rhill.id)
    if target_step
      target_step.step_status = :approved
      target_step.save!
    end

    approval.reload
    assert_equal 4, approval.approval_steps.count
    assert_equal 'approved', approval.approval_steps[0].step_status
    assert_equal 'canceled', approval.approval_steps[1].step_status
    assert_equal 'approved', approval.approval_steps[2].step_status
    assert_equal 'approved', approval.approval_steps[3].step_status
    assert_equal 'released', approval.status
  end

  test "should reject approval" do
    approval = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :pending,
      author_id: @user.id
    )
    step = approval.approval_steps.for_principal(@user).find_or_initialize_by(step: 1)
    step.step_status = :pending
    step.save!

    post :grant_approval, params: {
      project_id: @project.id,
      title: @page.title,
      version: @page.content.version,
      step_id: step.id,
      note: "Looks bad",
      status: "rejected"
    }

    assert_response :redirect
    step.reload
    assert_equal 'rejected', step.step_status
    assert_equal 'Looks bad', step.note
    approval.reload
    assert_equal 'rejected', approval.status
  end

  test "should reject approval without note" do
    approval = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :pending,
      author_id: @user.id
    )
    step = approval.approval_steps.for_principal(@user).find_or_initialize_by(step: 1)
    step.step_status = :pending
    step.save!

    post :grant_approval, params: {
      project_id: @project.id,
      title: @page.title,
      version: @page.content.version,
      step_id: step.id,
      note: "",
      status: "rejected"
    }

    assert_response :redirect
    assert_includes flash[:error], I18n.t(:wiki_approval_unable_note)
    step.reload
    assert_equal 'pending', step.step_status
    approval.reload
    assert_equal 'pending', approval.status
  end

  test "should cancel old approval after new version" do
    @page = WikiPage.find(11)
    approval = WikiApprovalWorkflow.find_by(page_id: @page.id, version:  @page.content.version)
    assert_equal 'pending', approval.status

    @page.content ||= WikiContent.create!(page: @page, text: 'test')
    content = @page.content.reload
    content.text = "new text new version"
    content.comments = "update to"
    content.author = @user
    content.save!
    content.reload
    @page.reload

    post :start_approval, params: {
      project_id: @project.id,
      title: @page.title,
      version: @page.content.version,
      steps: { "1" => [{ "principal_id" => @user.id.to_s }] },
      steps_typ: { "1" => "or" },
      note: "Approval started"
    }
    assert_response :redirect

    approval.reload
    assert_equal 'canceled', approval.status
  end

  test "should redirect to page status released" do
    @page = WikiPage.find_by(id: 11)
    approval = WikiApprovalWorkflow.find_by(page_id: @page.id, version:  @page.content.version)
    approval.status = :released
    approval.save!
    post :start_approval, params: {
      project_id: @project.id,
      title: @page.title,
      version: @page.content.version,
      steps: { "1" => [{ "principal_id" => @user.id.to_s }] },
      steps_typ: { "1" => "or" },
      note: "redirect"
    }
    assert_response :redirect
    assert_includes flash[:error], I18n.t(:wiki_approval_unable_start_status, :status => I18n.t("wiki_approval_workflow.status.released"))
  end

  test "should forward format js template" do
    approval = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :draft,
      author_id: @user.id
    )
    step1 = approval.approval_steps.for_principal(@user).find_or_initialize_by(step: 1)
    step1.step_status = :pending
    step1.save!

    get :forward_approval, params: {
      project_id: @project.id,
      title: @page.title,
      version: @page.content.version,
      step_id: step1.id
    }, xhr: true

    assert_response :success
    assert_equal 'text/javascript', @response.media_type
    assert_match 'Forward approval', @response.body

    options_count = @response.body.scan('<\/option>').size
    assert_equal 4, options_count

    assert_match 'Dave Lopper', @response.body
  end

  test "should grant format js template" do
    approval = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :draft,
      author_id: @user.id
    )
    step1 = approval.approval_steps.for_principal(@user).find_or_initialize_by(step: 1)
    step1.step_status = :pending
    step1.save!

    get :grant_approval, params: {
      project_id: @project.id,
      title: @page.title,
      version: @page.content.version,
      step_id: step1.id
    }, xhr: true

    assert_response :success
    assert_equal 'text/javascript', @response.media_type
    assert_match I18n.t(:label_wiki_approval_settings_enabled), @response.body
  end

  test "should return 404 no page" do
    get :start_approval, params: { project_id: @project.id, title: 'not found', version: @page.content.version }
    assert_response :not_found
  end

  test "should forward approval get group" do
    member = Member.new(project: @project, principal: @group)
    member.roles << @manager_role
    member.save!

    approval = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :draft,
      author_id: @user.id
    )
    step1 = approval.approval_steps.for_principal(@user).find_or_initialize_by(step: 1)
    step1.step_status = :pending
    step1.save!

    get :forward_approval, params: {
      project_id: @project.id,
      title: @page.title,
      version: @page.content.version,
      step_id: step1.id
    }, xhr: true

    assert_response :success
    assert_equal 'text/javascript', @response.media_type
    assert_match 'A Team', @response.body
    assert_match 'Dave Lopper', @response.body
  end

  test "should reject approval group cancel old" do
    set_session_user(User.find_by(id: 8))
    member = Member.new(project: @project, principal: @group)
    member.roles << @manager_role
    member.save!

    approval = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :pending,
      author_id: @admin.id
    )
    step = approval.approval_steps.for_principal(@dlopper).find_or_initialize_by(step: 1)
    step.step_status = :pending
    step.step_type = 1
    step.save!

    step2 = approval.approval_steps.for_principal(@group).find_or_initialize_by(step: 1)
    step2.step_status = :pending
    step2.step_type = 1
    step2.save!

    post :grant_approval, params: {
      project_id: @project.id,
      title: @page.title,
      version: @page.content.version,
      step_id: step2.id,
      note: "Looks bad",
      status: "rejected"
    }

    assert_response :redirect
    step2.reload
    assert_equal 'rejected', step2.step_status
    assert_equal 'Looks bad', step2.note
    step.reload
    assert_equal 'canceled', step.step_status
    approval.reload
    assert_equal 'rejected', approval.status
  end
end
