# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class MyPageTest < WikiApproval::Test::ControllerCase
  tests MyController

  def setup
    super
    set_session_user(@jsmith)

    # save myPage layout
    @jsmith.pref.my_page_layout = {
      'left' => ['my_wiki_drafts'],
      'right' => ['wiki_approval_queue']
    }
    @jsmith.pref.save!
  end

  def test_wiki_approval_blocks_select_on_my_page
    get :index
    assert_response :success

    # in select block
    assert_select "select#block-select" do
      assert_select "option[disabled='disabled']", text: I18n.t(:my_wiki_drafts)
      assert_select "option[disabled='disabled']", text: I18n.t(:wiki_approval_queue)
    end

    # 1. Prüfe, ob der Haupt-Container des Blocks existiert
    assert_select "div#block-my_wiki_drafts.mypage-box" do
      # 2. Prüfe die Überschrift inklusive der Anzahl (1)
      assert_select "h3", text: /My wiki drafts \(1\)/

      # 3. Prüfe, ob der "Delete"-Link korrekt generiert wurde
      assert_select "a[href='/my/remove_block?block=my_wiki_drafts']"

      # 4. Validiere die Tabelle und deren Header
      assert_select "table.list" do
        assert_select "thead tr th", text: "Project"
        assert_select "thead tr th", text: "Wiki page"
        assert_select "thead tr th", text: "Status"

        # 5. Prüfe die Datenzeile (den ersten Eintrag)
        assert_select "tbody tr.odd" do
          # Projekt-Link
          assert_select "td a[href='/projects/ecookbook']", text: "eCookbook"

          # Wiki-Seiten-Link mit Versionsparameter
          assert_select "td a[href='/projects/ecookbook/wiki/Page_with_sections?version=3']", text: "Page_with_sections"

          # Status und Kommentar
          assert_select "td", text: "In approval"
          assert_select "td", text: "in pending"

          # Den "View"-Button am Ende der Zeile
          assert_select "td.buttons a.icon-view", text: "View"
        end
      end
    end

    # 1. Haupt-Container für die Queue finden
    assert_select "div#block-wiki_approval_queue.mypage-box" do
      # 2. Überschrift mit der (0) prüfen
      assert_select "h3", text: /Wiki approval queue \(0\)/

      # 3. Den "No data"-Hinweis validieren
      # Redmine nutzt hierfür standardmäßig das <p>-Tag mit der Klasse 'nodata'
      assert_select "p.nodata", text: "No data to display"

      # 4. Sicherstellen, dass KEINE Tabelle gerendert wird
      assert_select "table.list", false, "Table should not be present when queue is empty"

      # 5. Prüfen, ob der Löschen-Link trotzdem vorhanden ist
      assert_select "a[href='/my/remove_block?block=wiki_approval_queue']"
    end
  end

  def test_my_page_more_drafts
    @page = WikiPage.find_by(title: 'CookBook_documentation')
    @page.content ||= WikiContent.create!(page: @page, text: 'test')

    approval = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :pending,
      author_id: @jsmith.id
    )
    step = approval.approval_steps.for_principal(@dlopper).find_or_initialize_by(step: 1)
    step.step_status = :pending
    step.save!

    get :index
    assert_response :success

    # Den Hauptblock für die Entwürfe ansteuern
    assert_select "div#block-my_wiki_drafts" do
      # 1. Die Überschrift mit der korrekten Anzahl (2) prüfen
      assert_select "h3", text: /My wiki drafts \(2\)/

      # 2. Die Tabellenstruktur validieren
      assert_select "table.list" do
        # Header-Prüfung
        assert_select "thead tr th", text: "Project"
        assert_select "thead tr th", text: "Wiki page"

        # 3. Den ersten Eintrag prüfen (Klasse 'even')
        assert_select "tbody tr.even" do
          assert_select "td a", text: "eCookbook"
          assert_select "td a", text: "Page_with_sections"
          assert_select "td", text: "In approval"
          assert_select "td", text: "in pending"
          assert_select "td.buttons a.icon-view[href='/projects/ecookbook/wiki/Page_with_sections?version=3']"
        end

        # 4. Den zweiten Eintrag prüfen (Klasse 'odd')
        assert_select "tbody tr.odd" do
          assert_select "td a", text: "eCookbook"
          assert_select "td a", text: "CookBook_documentation"
          assert_select "td", text: "In approval"
          # Hier ist das Kommentar-Feld im HTML leer
          assert_select "td", text: ""
          assert_select "td.buttons a.icon-view[href='/projects/ecookbook/wiki/CookBook_documentation?version=3']"
        end

        # 5. Anzahl der Zeilen im Body verifizieren
        assert_select "tbody tr", count: 2
      end
    end
    # 1. Haupt-Container für die Queue finden
    assert_select "div#block-wiki_approval_queue.mypage-box" do
      # 2. Überschrift mit der (0) prüfen
      assert_select "h3", text: /Wiki approval queue \(0\)/
    end
  end

  def test_my_page_more_queue
    @page = WikiPage.find_by(title: 'CookBook_documentation')
    @page.content ||= WikiContent.create!(page: @page, text: 'test')

    approval = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :pending,
      author_id: @dlopper.id
    )
    step = approval.approval_steps.for_principal(@jsmith).find_or_initialize_by(step: 1)
    step.step_status = :pending
    step.save!

    get :index
    assert_response :success

    # 1. Prüfe, ob der Haupt-Container des Blocks existiert
    assert_select "div#block-my_wiki_drafts.mypage-box" do
      # 2. Prüfe die Überschrift inklusive der Anzahl (1)
      assert_select "h3", text: /My wiki drafts \(1\)/
    end

    # Den Block für die Freigabe-Warteschlange ansteuern
    assert_select "div#block-wiki_approval_queue" do
      # 1. Überschrift mit Anzahl (1) prüfen
      assert_select "h3", text: /Wiki approval queue \(1\)/

      # 2. Die Tabellenstruktur und spezifische Header validieren
      assert_select "table.list" do
        assert_select "thead tr" do
          assert_select "th", text: "Project"
          assert_select "th", text: "Workflow starter" # Wichtig für die Queue
          assert_select "th", text: "Step"
        end

        # 3. Den Eintrag in der Tabelle prüfen
        assert_select "tbody tr.even" do
          # Projekt und Wiki-Seite
          assert_select "td a[href='/projects/ecookbook']", text: "eCookbook"
          assert_select "td a[href='/projects/ecookbook/wiki/CookBook_documentation?version=3']", text: "CookBook_documentation"

          # Workflow-Details
          assert_select "td", text: "Dave Lopper" # Workflow starter
          assert_select "td", text: "1"           # Aktueller Step

          # Den View-Button am Ende
          assert_select "td.buttons a.icon-view", text: "View"
        end

        # Sicherstellen, dass genau eine Zeile vorhanden ist
        assert_select "tbody tr", count: 1
      end
    end
  end

  def test_my_page_queue_group
    @page = WikiPage.find_by(title: 'CookBook_documentation')
    @page.content ||= WikiContent.create!(page: @page, text: 'test')

    @group.users << @jsmith
    Member.create!(project: @project, principal: @group, roles: [@developer_role])

    approval = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :pending,
      author_id: @dlopper.id
    )
    step = approval.approval_steps.for_principal(@group).find_or_initialize_by(step: 1)
    step.step_status = :pending
    step.save!

    get :index
    assert_response :success

    # 1. Den Block in der rechten Spalte suchen
    assert_select "#list-right #block-wiki_approval_queue" do
      # 2. Titel und Counter (1) prüfen
      assert_select "h3", text: /Wiki approval queue \(1\)/

      # 3. Den Löschen-Button validieren
      assert_select "a.icon-close[href='/my/remove_block?block=wiki_approval_queue']"

      # 4. Tabelleninhalt prüfen
      assert_select "table.list" do
        # Header-Check für die speziellen Spalten
        assert_select "thead th", text: "Workflow starter"
        assert_select "thead th", text: "Step"

        # Datenzeile prüfen
        assert_select "tbody tr.even" do
          # Projekt & Wiki-Link
          assert_select "td a[href='/projects/ecookbook']", text: "eCookbook"
          assert_select "td a[href*='CookBook_documentation?version=3']", text: "CookBook_documentation"

          # Workflow-spezifische Daten
          assert_select "td", text: "Dave Lopper" # Starter
          assert_select "td", text: "1"           # Aktueller Schritt

          # Action Button
          assert_select "td.buttons a.icon-view", text: "View"
        end
      end
    end
  end

  def test_my_page_more_drafts_in_progress
    @page = WikiPage.find_by(title: 'CookBook_documentation')
    @page.content ||= WikiContent.create!(page: @page, text: 'test')

    approval = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :pending,
      author_id: @jsmith.id
    )
    step = approval.approval_steps.for_principal(@dlopper).find_or_initialize_by(step: 1)
    step.step_status = :pending
    step.save!

    WikiApprovalDraft.create!(
      page_id: @page.id,
      author_id: @jsmith.id,
      text: "newText"
    )

    get :index
    assert_response :success

    # Den Hauptblock für die Entwürfe ansteuern
    assert_select "div#block-my_wiki_drafts" do
      # 1. Die Überschrift mit der korrekten Anzahl (3) prüfen
      assert_select "h3", text: /My wiki drafts \(3\)/

      # 2. Die Tabellenstruktur validieren
      assert_select "table.list" do
        # Header-Prüfung
        assert_select "thead tr th", text: "Project"
        assert_select "thead tr th", text: "Wiki page"
        assert_select "thead tr th", text: "Status"
        assert_select "thead tr th", text: "Comment"
        assert_select "thead tr th", text: "Created"
        assert_select "thead tr th", text: "Updated"

        # 3. Erste Zeile (odd)
        assert_select "tbody tr.odd:nth-of-type(1)" do
          assert_select "td a", text: "eCookbook"
          assert_select "td a", text: "CookBook_documentation"
          assert_select "td", text: "In approval"
          assert_select "td", text: ""
          assert_select "td.buttons a.icon-view[href='/projects/ecookbook/wiki/CookBook_documentation?version=3']"
        end

        # 4. Zweite Zeile (even)
        assert_select "tbody tr.even" do
          assert_select "td a", text: "eCookbook"
          assert_select "td a", text: "CookBook_documentation"
          assert_select "td", text: "Draft in progress"
          assert_select "td", text: ""
          assert_select "td.buttons a.icon-view[href='/projects/ecookbook/wiki/CookBook_documentation/edit']"
        end

        # 5. Dritte Zeile (odd)
        assert_select "tbody tr.odd:nth-of-type(2)" do
          assert_select "td a", text: "eCookbook"
          assert_select "td a", text: "Page_with_sections"
          assert_select "td", text: "In approval"
          assert_select "td", text: "in pending"
          assert_select "td.buttons a.icon-view[href='/projects/ecookbook/wiki/Page_with_sections?version=3']"
        end

        # 6. Anzahl der Zeilen im Body verifizieren
        assert_select "tbody tr", count: 3
      end
    end

    # 7. Haupt-Container für die Queue finden
    assert_select "div#block-wiki_approval_queue.mypage-box" do
      # 8. Überschrift mit der (0) prüfen
      assert_select "h3", text: /Wiki approval queue \(0\)/
    end
  end
end
