require File.expand_path('../test_helper', __dir__)

class WikiApprovalMacrosTest < WikiApproval::Test::ControllerCase
  tests WikiController

  def setup
    super
    @page = WikiPage.find(11)
    set_session_user(@jsmith)
    Setting.gravatar_enabled = '1'
    Setting.gravatar_default = 'identicon'
  end

  test "returns the revision number when approved" do
    @page.content.attributes = {
      text: "revision: {{rwa_revision}}",
      comments: "returns revision",
      author_id: 1
    }
    @page.content.save!

    WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :released,
      author_id: User.current.id
    )

    get :show, params: { project_id: @project.id, id: @page.title, version: @page.content.version }
    assert_select 'div.wiki.wiki-page' do
      assert_select 'p', 'revision: 2'
    end
  end

  test "returns not a revision number when in draft" do
    @page.content.attributes = {
      text: "revision: {{rwa_revision}}",
      comments: "returns revision",
      author_id: 1
    }
    @page.content.save!

    WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :draft,
      author_id: User.current.id
    )

    get :show, params: { project_id: @project.id, id: @page.title, version: @page.content.version }
    assert_select 'div.wiki.wiki-page' do
      assert_select 'p', 'revision:'
    end
  end

  test "renders status badge when workflow is released" do
    @page.content.attributes = {
      text: "{{rwa_status}}",
      comments: "returns status badge",
      author_id: 1
    }
    @page.content.save!

    WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :released,
      author_id: User.current.id
    )

    get :show, params: {project_id: @project.id, id: @page.title, version: @page.content.version}
    assert_select 'div.wiki.wiki-page' do
      assert_select 'span.badge' do
        assert_select '.badge-status-closed'
        assert_select 'span', 'Released'
      end
    end
  end

  test "returns plain status text when using text parameter" do
    @page.content.attributes = {
      text: "status: {{rwa_status(text)}}",
      comments: "returns status text",
      author_id: 1
    }
    @page.content.save!

    WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :released,
      author_id: User.current.id
    )

    get :show, params: { project_id: @project.id, id: @page.title, version: @page.content.version}

    assert_select 'div.wiki.wiki-page' do
      assert_select 'p', 'status: Released'
    end
  end

  test "renders workflow updated_at timestamp in redmine format" do
    @page.content.attributes = {
      text: "updated: {{rwa_updated_at}}",
      comments: "returns workflow updated_at",
      author_id: 1
    }
    @page.content.save!
    workflow = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :released,
      author_id: User.current.id
    )
    workflow.update_column(:updated_at, Time.utc(2026, 4, 25, 19, 48))

    get :show, params: { project_id: @project.id, id: @page.title, version: @page.content.version }

    assert_select 'div.wiki.wiki-page' do
      assert_select 'p', "updated: 04/25/2026 07:48 PM"
    end
  end

  test "renders relative workflow updated_at with tooltip" do
    @page.content.attributes = {
      text: "updated: {{rwa_updated_at(relative)}}",
      comments: "returns relative workflow updated_at",
      author_id: 1
    }
    @page.content.save!
    workflow = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :released,
      author_id: User.current.id
    )
    workflow.update_column(:updated_at, 1.month.ago)

    get :show, params: { project_id: @project.id, id: @page.title, version: @page.content.version }
    assert_select 'div.wiki.wiki-page' do
      assert_select 'span[title]' do
        assert_select '*', "about 1 month"
      end
    end
  end

  test "returns the diff link" do
    @page.content.attributes = {
      text: "diff: {{rwa_diff}}",
      comments: "returns diff link",
      author_id: 1
    }
    @page.content.save!

    WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :released,
      author_id: User.current.id
    )

    get :show, params: { project_id: @project.id, id: @page.title, version: @page.content.version }
    assert_select 'div.wiki.wiki-page' do
      assert_select 'p' do
        assert_select 'a',
          text: 'diff',
          href: %r{/projects/ecookbook/wiki/Page_with_sections/diff\?version=4&version_from=2}
      end
    end
  end

  test "returns all workflow step users" do
    @page.content.attributes = {
      text: "{{rwa_users}}",
      comments: "returns rwa_users",
      author_id: 1
    }
    @page.content.save!

    approval = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :pending,
      author_id: User.current.id
    )
    step = approval.approval_steps.for_principal(@dlopper).find_or_initialize_by(step: 1)
    step.step_status = :approved
    step.note = "test note"
    step.save!

    step = approval.approval_steps.for_principal(@rhill).find_or_initialize_by(step: 2)
    step.step_status = :pending
    step.save!

    get :show, params: { project_id: @project.id, id: @page.title, version: @page.content.version }
    assert_select 'div.wiki.wiki-page' do
      assert_select 'div#approval ul li', 2
      assert_select 'div#approval ul li:nth-of-type(1) .rwa-user div', text: 'Dave Lopper'
      assert_select 'div#approval .rwa-note', 0
      assert_select 'div#approval ul li:nth-of-type(2) .rwa-user div', text: 'Robert Hill'
      assert_select 'div#approval .rwa-user [class*="avatar"]', 0
    end
  end

  test "returns workflow step users starter" do
    @page.content.attributes = {
      text: "{{rwa_users(starter=true, note=true, userimage=true)}}",
      comments: "returns rwa_users with starter note image",
      author_id: 1
    }
    @page.content.save!

    approval = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :pending,
      author_id: User.current.id
    )
    step = approval.approval_steps.for_principal(@dlopper).find_or_initialize_by(step: 1)
    step.step_status = :approved
    step.note = "test note"
    step.save!

    step = approval.approval_steps.for_principal(@rhill).find_or_initialize_by(step: 2)
    step.step_status = :pending
    step.save!

    get :show, params: { project_id: @project.id, id: @page.title, version: @page.content.version }

    assert_select 'div.wiki.wiki-page' do
      assert_select 'div#approval ul li', 3
      assert_select 'div#approval ul li:nth-of-type(1) .rwa-user div', text: 'John Smith'
      assert_select 'div#approval ul li:nth-of-type(2)' do
        assert_select '.rwa-user div', text: 'Dave Lopper'
        assert_select '.rwa-note', text: 'test note'
      end
      assert_select 'div#approval ul li:nth-of-type(3) .rwa-user div', text: 'Robert Hill'
      assert_select 'div#approval .rwa-user [class*="avatar"]', 3
    end
  end

  test "returns workflow step users only step 1" do
    @page.content.attributes = {
      text: "{{rwa_users(starter=false, step=1, status=true, mouseover=true, userlink=true)}}",
      comments: "returns rwa_users with starter note image",
      author_id: 1
    }
    @page.content.save!

    approval = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :pending,
      author_id: User.current.id
    )
    step = approval.approval_steps.for_principal(@dlopper).find_or_initialize_by(step: 1)
    step.step_status = :approved
    step.note = "test note"
    step.save!

    step = approval.approval_steps.for_principal(@rhill).find_or_initialize_by(step: 2)
    step.step_status = :pending
    step.save!

    get :show, params: { project_id: @project.id, id: @page.title, version: @page.content.version }
    assert_select 'div.wiki.wiki-page' do
      assert_select 'div#approval ul li', 1
      assert_select 'div#approval ul li:nth-of-type(1)' do
        assert_select '.rwa-user a.user.active', text: 'Dave Lopper', href: '/users/3'
        assert_select '.rwa-status', text: 'Approved', title: 'days ago less than a minute'
        assert_select '.rwa-note', 0
        assert_select '.rwa-user [class*="avatar"]', 0
      end
    end
  end

  test "returns workflow step users only step 1 without boolen" do
    @page.content.attributes = {
      text: "{{rwa_users(starter=false, step=1, status, mouseover, userlink)}}",
      comments: "returns rwa_users with starter note image",
      author_id: 1
    }
    @page.content.save!

    approval = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :pending,
      author_id: User.current.id
    )
    step = approval.approval_steps.for_principal(@dlopper).find_or_initialize_by(step: 1)
    step.step_status = :approved
    step.note = "test note"
    step.save!

    step = approval.approval_steps.for_principal(@rhill).find_or_initialize_by(step: 2)
    step.step_status = :pending
    step.save!

    get :show, params: { project_id: @project.id, id: @page.title, version: @page.content.version }
    assert_select 'div.wiki.wiki-page' do
      assert_select 'div#approval ul li', 1
      assert_select 'div#approval ul li:nth-of-type(1)' do
        assert_select '.rwa-user a.user.active', text: 'Dave Lopper', href: '/users/3'
        assert_select '.rwa-status', text: 'Approved', title: 'days ago less than a minute'
        assert_select '.rwa-note', 0
        assert_select '.rwa-user [class*="avatar"]', 0
      end
    end
  end

  test "returns workflow step users only approved" do
    @page.content.attributes = {
      text: "{{rwa_users(starter=false,status,mouseover,userlink,approved)}}",
      comments: "returns rwa_users with starter note image",
      author_id: 1
    }
    @page.content.save!

    approval = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :pending,
      author_id: User.current.id
    )
    step = approval.approval_steps.for_principal(@dlopper).find_or_initialize_by(step: 1)
    step.step_status = :approved
    step.note = "test note"
    step.save!

    step = approval.approval_steps.for_principal(@rhill).find_or_initialize_by(step: 1)
    step.step_status = :pending
    step.save!

    get :show, params: { project_id: @project.id, id: @page.title, version: @page.content.version }
    assert_select 'div.wiki.wiki-page' do
      assert_select 'div#approval ul li', 1
      assert_select 'div#approval ul li:nth-of-type(1)' do
        assert_select '.rwa-user a.user.active', text: 'Dave Lopper', href: '/users/3'
        assert_select '.rwa-status', text: 'Approved', title: 'days ago less than a minute'
        assert_select '.rwa-note', 0
        assert_select '.rwa-user [class*="avatar"]', 0
      end
    end
  end
end
