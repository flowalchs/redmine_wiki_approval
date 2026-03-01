# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class WikiApprovalActivityControllerTest < WikiApproval::Test::ControllerCase
  tests ActivitiesController
  def setup
    super
    set_session_user(@admin)
  end

  test 'activity provider is registered' do
    providers = Redmine::Activity.available_event_types
    assert_includes providers, 'wiki_approval_workflow'
  end

  test 'activity provider 2 entry' do
    get(
      :index,
      :params => {
        :format => 'atom',
        :with_subprojects => 0,
        :show_wiki_approval_workflow => 1
      }
    )
    assert_response :success
    assert_select 'feed' do
      assert_select 'entry', :count => 5
      assert_select 'link[rel=self][href=?]', 'http://test.host/activity.atom?show_wiki_approval_workflow=1&with_subprojects=0'
      assert_select 'link[rel=alternate][href=?]', 'http://test.host/activity?show_wiki_approval_workflow=1&with_subprojects=0'
      assert_select 'entry' do
        assert_select 'link[href=?]', 'http://test.host/projects/ecookbook/wiki/Page_with_sections/3'
        assert_select 'link[href=?]', 'http://test.host/projects/ecookbook/wiki/Page_with_sections/2'
      end
    end
  end

  test 'activity provider with sub projects' do
    subproject = @project3
    # Ensure subproject has a wiki
    subproject.create_wiki(start_page: 'Wiki')
    # Add a wiki page to the subproject and update its content
    @page = WikiPage.create!(wiki: subproject.wiki, title: 'Subproject Page')
    content = WikiContent.create!(page: @page, text: 'content', author_id: 1, updated_on: Time.now)
    WikiApprovalWorkflow.create!(
      wiki_page_id: @page.id,
      wiki_version_id: content.version,
      status: :draft,
      author_id: @user.id
    )

    get(
      :index,
      :params => {
        :format => 'atom',
        :with_subprojects => 1,
        :show_wiki_approval_workflow => 1
      }
    )
    assert_response :success
    assert_select 'feed' do
      assert_select 'entry', :count => 6
      assert_select 'entry' do
        assert_select 'link[href=?]', 'http://test.host/projects/subproject1/wiki/Subproject_Page/1'
        assert_select 'link[href=?]', 'http://test.host/projects/ecookbook/wiki/Page_with_sections/3'
        assert_select 'link[href=?]', 'http://test.host/projects/ecookbook/wiki/Page_with_sections/2'
      end
    end
  end

  test 'activity provider no permission' do
    set_session_user(@admin)
    subproject = @project3
    # Ensure subproject has a wiki
    subproject.create_wiki(start_page: 'Wiki')
    # Add a wiki page to the subproject and update its content
    @page = WikiPage.create!(wiki: subproject.wiki, title: 'Subproject Page')
    content = WikiContent.create!(page: @page, text: 'content', author_id: 1, updated_on: Time.now)
    WikiApprovalWorkflow.create!(
      wiki_page_id: @page.id,
      wiki_version_id: content.version,
      status: :draft,
      author_id: @user.id
    )

    get(
      :index,
      :params => {
        :id => subproject.identifier,
        :format => 'atom',
        :with_subprojects => 0,
        :show_wiki_approval_workflow => 1
      }
    )
    assert_response :success
    assert_select 'link[href=?]', 'http://test.host/projects/subproject1/wiki/Subproject_Page/1'

    # no permission
    set_session_user(@jsmith)
    get(
      :index,
      :params => {
        :id => subproject.identifier,
        :format => 'atom',
        :with_subprojects => 0,
        :show_wiki_approval_workflow => 1
      }
    )
    assert_response :success
    assert_select 'link[href=?]', 'http://test.host/projects/subproject1/wiki/Subproject_Page/1', 0
  end

  test 'activity provider should filter by subprojects and date range and group' do
    set_session_user(@admin)
    
    # Friert "jetzt" ein, um TZ-/Tageswechsel-Flakes zu vermeiden
    travel_to Time.current do
      # 1) Isolierte Projektstruktur
      root = Project.generate!(identifier: "act-test1", name: 'Activity Root')
      sub  = Project.generate!(identifier: "act-sub-test1",
                               name: 'Activity Sub', parent: root)

      root.enable_module!('wiki')
      root.enable_module!('wiki_approval')
      sub.enable_module!('wiki')
      sub.enable_module!('wiki_approval')

      root.create_wiki(start_page: 'RootStart') unless root.wiki
      sub.create_wiki(start_page: 'SubStart')   unless sub.wiki

      # Zwei Wiki-Seiten im Subprojekt:
      page_sub  = WikiPage.create!(wiki: sub.wiki,  title: 'SubPage')
      page_sub2 = WikiPage.create!(wiki: sub.wiki,  title: 'SubPage2')

      # 2) Zeitpunkte (3 Tage: von t_now-2d bis t_now inkl.)
      t_now = Time.current

      # SubPage: 1 Workflow-Event (soll erscheinen)
      wf_sub = WikiApprovalWorkflow.create!(
        wiki_page: page_sub, wiki_version_id: 1, status: 20,
        author_id: @admin.id, created_at: t_now
      )

      # SubPage2: 1 Workflow-Event + 2 Statusänderungen (Status erscheinen NICHT im Activity-Stream,
      # da kein eigener Provider vorhanden ist; also KEINE Gruppierung)
      wf_sub2 = WikiApprovalWorkflow.create!(
        wiki_page: page_sub2, wiki_version_id: 2, status: 20,
        author_id: @admin.id, created_at: t_now
      )
      # Zwei Änderungen auf derselben Seite/Workflow -> keine Activity-Einträge ohne Status-Provider
      WikiApprovalWorkflowStatus.create!(
        wiki_approval_workflow: wf_sub2, status: 20,
        author_id: @admin.id, created_at: t_now + 5.minutes
      )
      WikiApprovalWorkflowStatus.create!(
        wiki_approval_workflow: wf_sub2, status: 70,
        author_id: @admin.id, created_at: t_now + 10.minutes
      )

      # Root-Projekt: außerhalb des Fensters -> soll gefiltert werden
      page_root = WikiPage.create!(wiki: root.wiki, title: 'RootPage')
      wf_root = WikiApprovalWorkflow.create!(
        wiki_page: page_root, wiki_version_id: 3, status: 20,
        author_id: @admin.id, created_at: t_now + 2.minutes
      )
      WikiApprovalWorkflowStatus.create!(
        wiki_approval_workflow: wf_root, status: 20,
        author_id: @admin.id, created_at: t_now + 2.minutes
      )

      # --- 4) Request mit 3-Tage-Fenster + Subprojekte + Plugin-Scope ---
      get :index, params: {
        id: root.identifier,
        from: t_now.to_date.to_s,
        to:   (t_now - 2.days).to_date.to_s,
        with_subprojects: 1,
        show_wiki_approval_workflow: 1
      }

      assert_response :success

      assert_select 'div#activity' do
        # Es gibt genau 1 Tagesblock in deinem Snippet
        assert_select 'dl', count: 1

        assert_select 'dl' do
          # Insgesamt 6 <dt>-Einträge
          assert_select 'dt.workflows.icon.icon-workflows', count: 6

          # Davon 3 mit Gruppierung (class beinhaltet 'grouped')
          assert_select 'dt.workflows.icon.icon-workflows.grouped.me', count: 3

          # Und damit 3 ohne Gruppierung (ohne .grouped)
          assert_select 'dt.workflows.icon.icon-workflows.me:not(.grouped)', count: 3

          # Zu jedem grouped-<dt> gehört ein <dd class="grouped">
          assert_select 'dd.grouped', count: 3

          # Und 3 normale <dd> ohne grouped
          assert_select 'dd:not(.grouped)', count: 3

          # Links Subprojekt (SubPage2) – kommt mehrfach (einmal ungegrouped + mehrfach grouped)
          assert_select 'dt a[href="/projects/act-sub-test1/wiki/SubPage2/2"]', minimum: 3
          # Links Subprojekt (SubPage)
          assert_select 'dt a[href="/projects/act-sub-test1/wiki/SubPage/1"]', count: 1
          # Links Root
          assert_select 'dt a[href="/projects/act-test1/wiki/RootPage/3"]', minimum: 2

          # Inhalte/Labels
          assert_select 'dd span.description', text: /In approval|Released/, minimum: 1
          assert_select 'dd span.author a.user', text: /Redmine Admin/, minimum: 1

          # Bonus: spezifischer Check auf die Kombination 'grouped me' und korrekten Link
          assert_select 'dt.workflows.icon.icon-workflows.grouped.me a[href="/projects/act-sub-test1/wiki/SubPage2/2"]', minimum: 1

          # Bonus: sicherstellen, dass die ungegroupte SubPage2-Zeile existiert
          assert_select 'dt.workflows.icon.icon-workflows.me:not(.grouped) a[href="/projects/act-sub-test1/wiki/SubPage2/2"]', count: 1

          # Bonus: sicherstellen, dass die ungegroupte SubPage-Zeile existiert
          assert_select 'dt.workflows.icon.icon-workflows.me:not(.grouped) a[href="/projects/act-sub-test1/wiki/SubPage/1"]', count: 1
        end
      end
    end
  end
end
