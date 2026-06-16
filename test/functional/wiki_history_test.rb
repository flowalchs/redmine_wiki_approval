require File.expand_path('../test_helper', __dir__)

class WikiHistoryTest < WikiApproval::Test::ControllerCase
  tests WikiController

  def setup
    super
    @page = WikiPage.find(11)
    set_session_user(@jsmith)
  end

  test 'wiki history approval table' do
    get :history, params: { project_id: @project.id, id: @page.title }

    assert_response :success

    assert_select 'table.wiki-page-versions'
    assert_select 'table.wiki-page-versions thead th', count: 12
    assert_select 'thead th', text: '#'
    assert_select 'thead th', text: 'Updated'
    assert_select 'thead th', text: 'Author'
    assert_select 'thead th', text: 'Comment'
    assert_select 'thead th', text: 'Status'
    assert_select 'thead th', text: 'Steps'
    assert_select 'thead th', text: 'Revision'
    assert_select 'thead th', text: 'Workflow starter'
    assert_select 'thead th', text: 'Approval workflow'

    # --- Reihenfolge der Approval-Header ---
    header_texts = css_select('table.wiki-page-versions thead th').map(&:text)

    assert_equal [
      '#', '', '', 'Updated', 'Author', 'Comment',
      'Status', 'Steps', 'Revision', 'Workflow starter',
      'Approval workflow', ''
    ].map(&:strip), header_texts.map(&:strip)

    assert_select 'tbody tr.wiki-page-version', minimum: 1
    assert_select 'td .approval', minimum: 1
    assert_select '.approval .rwa-user a.user', minimum: 1
    assert_select '.approval .rwa-status[title*="Step"]', minimum: 1
    assert_select '.approval .rwa-status', text: /In approval|Approved/
  end

  test 'wiki history disable approval' do
    @project.disable_module! :wiki_approval

    get :history, params: { project_id: @project.id, id: @page.title }

    assert_response :success

    # --- Grundtabelle vorhanden ---
    assert_select 'table.wiki-page-versions'
    assert_select 'tbody tr.wiki-page-version', minimum: 1
    # --- KEINE Approval-Container ---
    assert_select '.approval', count: 0
    assert_select '.rwa-user', count: 0
    assert_select '.rwa-status', count: 0
    assert_select '.rwa-note', count: 0
    assert_select 'thead th', text: 'Status', count: 0
    assert_select 'thead th', text: 'Steps', count: 0
    assert_select 'thead th', text: 'Revision', count: 0
    assert_select 'thead th', text: 'Workflow starter', count: 0
    assert_select 'thead th', text: 'Approval workflow', count: 0

    # --- Erwartete Anzahl Header (Standard-Layout) ---
    header_texts = css_select('thead th').map(&:text).map(&:strip)
    assert_equal [
      '#', '', '', 'Updated', 'Author', 'Comment', ''
    ], header_texts
  end

  test 'wiki history approval no workflow page 1' do
    @page = WikiPage.find(1)

    get :history, params: { project_id: @project.id, id: @page.title }

    assert_response :success
    assert_select 'table.wiki-page-versions', count: 1
    assert_select 'table.wiki-page-versions thead tr', count: 1
    assert_select 'table.wiki-page-versions tbody tr.wiki-page-version', count: 3
    assert_select 'table.wiki-page-versions tr', count: 4

    # --- Keine Approval-Elemente ---
    assert_select '.approval', count: 0
    assert_select '.rwa-user', count: 0
    assert_select '.rwa-status', count: 0
    assert_select '.rwa-note', count: 0

    # --- Keine Approval-Header ---
    assert_select 'thead th', text: /Status|Steps|Revision|Workflow/, count: 0
  end

  test 'wiki history approval with workflow page 1' do
    @page = WikiPage.find(1)
    2.times do |i|
      @page.content.text = "content #{i}"
      @page.content.author = @admin
      @page.content.save!
      WikiApprovalWorkflow.create!(
        page_id: @page.id,
        version: @page.content.version,
        status: :draft,
        author_id: @admin.id
      )
    end
    2.times do |i|
      @page.content.text = "content 2.#{i}"
      @page.content.author = @admin
      @page.content.save!
      WikiApprovalWorkflow.create!(
        page_id: @page.id,
        version: @page.content.version,
        status: :published,
        author_id: @jsmith.id
      )
    end
    get :history, params: { project_id: @project.id, id: @page.title }

    assert_response :success
    assert_select 'table.wiki-page-versions', count: 1
    assert_select 'table.wiki-page-versions thead tr', count: 1
    assert_select 'table.wiki-page-versions tbody tr.wiki-page-version', count: 7

    rows = css_select('table.wiki-page-versions tbody tr.wiki-page-version')
    assert_equal 7, rows.size

    rows.each_with_index do |row, index|
      cells = row.css('td')

      # Spaltenindex:
      # 0:# 1:cb 2:cb 3:Updated 4:Author 5:Comment
      # 6:Status 7:Steps 8:Revision
      # 9:Workflow starter 10:Approval workflow

      revision = cells[8].text.strip
      approvals = cells[9].css('.approval').any?

      case index
      when 0, 1
        # Version 7, 6
        assert_match /^\d+$/, revision, "Revision expected in row #{index}"
        assert approvals, "Approval expected in row #{index}"

      when 2, 3
        # Version 5, 4
        assert revision.blank?, "No revision expected in row #{index}"
        assert approvals, "Approval expected in row #{index}"

      else
        # Version <= 3
        assert revision.blank?, "No revision expected in row #{index}"
        assert cells[9].text.strip.blank?, "No workflow starter expected in row #{index}"
        assert cells[10].text.strip.blank?, "No approval workflow expected in row #{index}"
      end
    end
  end

  test 'wiki history approval with workflow page 1 pageing' do
    @page = WikiPage.find(1)
    20.times do |i|
      @page.content.text = "content #{i}"
      @page.content.author = @admin
      @page.content.save!
      WikiApprovalWorkflow.create!(
        page_id: @page.id,
        version: @page.content.version,
        status: :draft,
        author_id: @admin.id
      )
    end
    20.times do |i|
      @page.content.text = "content 2.#{i}"
      @page.content.author = @admin
      @page.content.save!
      WikiApprovalWorkflow.create!(
        page_id: @page.id,
        version: @page.content.version,
        status: :published,
        author_id: @jsmith.id
      )
    end
    get :history, params: { project_id: @project.id, id: @page.title, page: 1, per_page: 25 }

    assert_response :success

    assert_select 'span.pagination'
    assert_select 'span.items', text: '(1-25/43)'
    assert_select 'ul.pages li.current', text: '1'
    assert_select 'ul.pages li.page a', text: '2'
    assert_select 'ul.pages li.next a'

    # Approval existiert
    assert_select 'tbody .approval', minimum: 1

    # Keine Approval-Daten außerhalb der Tabelle
    assert_select '.approval', count: css_select('tbody tr.wiki-page-version')
      .sum { |tr| tr.css('.approval').size }
  end

  test 'wiki history approval with workflow page 1 pageing 2' do
    @page = WikiPage.find(1)
    20.times do |i|
      @page.content.text = "content #{i}"
      @page.content.author = @admin
      @page.content.save!
      WikiApprovalWorkflow.create!(
        page_id: @page.id,
        version: @page.content.version,
        status: :draft,
        author_id: @admin.id
      )
    end
    20.times do |i|
      @page.content.text = "content 2.#{i}"
      @page.content.author = @admin
      @page.content.save!
      WikiApprovalWorkflow.create!(
        page_id: @page.id,
        version: @page.content.version,
        status: :published,
        author_id: @jsmith.id
      )
    end
    get :history, params: { project_id: @project.id, id: @page.title, page: 2, per_page: 25 }

    assert_response :success
    # --- Pagination sichtbar ---
    assert_select 'span.pagination'
    assert_select 'span.items', text: '(26-43/43)'

    # --- Navigation ---
    assert_select 'ul.pages li.current', text: '2'
    assert_select 'ul.pages li.previous.page a[href*="page=1"]'
    assert_select 'ul.pages li.next span', text: /Next/

    # --- Exakte Anzahl der Zeilen (Page 2) ---
    assert_select 'tbody tr.wiki-page-version', count: 18

    # --- Keine Revisionen auf Page 2 ---
    css_select('tbody tr.wiki-page-version').each_with_index do |row, index|
      cells = row.css('td')
      revision_cell = cells[8] # Revision-Spalte

      assert revision_cell.text.strip.blank?,
            "Revision should be empty on page 2 (row #{index})"
    end

    # --- Approval weiterhin vorhanden (Canceled + Workflow starter) ---
    assert_select 'tbody .approval', minimum: 1
    assert_select 'tbody .approval .rwa-user a.user', minimum: 1
  end

  test 'wiki history approval with workflow approved' do
    @page = WikiPage.find(1)

    @page.content.text = "content 1"
    @page.content.author = @admin
    @page.content.save!
    approval = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :draft,
      author_id: @admin.id
    )
    step = approval.approval_steps.for_principal(@dlopper).find_or_initialize_by(step: 1)
    step.step_status = :pending
    step.note = "test pending"
    step.save!

    @page.content.text = "content 2"
    @page.content.author = @admin
    @page.content.save!
    approval = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :draft,
      author_id: @admin.id
    )
    step = approval.approval_steps.for_principal(@dlopper).find_or_initialize_by(step: 1)
    step.step_status = :approved
    step.note = "test approved"
    step.save!

    @page.content.text = "content 3"
    @page.content.author = @admin
    @page.content.save!
    approval = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :draft,
      author_id: @admin.id
    )
    step = approval.approval_steps.for_principal(@dlopper).find_or_initialize_by(step: 1)
    step.step_status = :rejected
    step.note = "test rejected"
    step.save!

    get :history, params: { project_id: @project.id, id: @page.title }

    assert_response :success

    rows = css_select('tbody tr.wiki-page-version')
    assert_equal 6, rows.size

    # Hilfsfunktion: Text aus Spalte holen
    def cell_text(row, index)
      row.css('td')[index].text.strip
    end

    # Spaltenindex:
    # 6:Status 7:Steps 8:Revision 10:Approval workflow

    # --- Version 6 (row 0) ---
    row = rows[0]
    assert_equal 'Rejected', cell_text(row, 6)
    assert_equal '1',        cell_text(row, 7)
    assert_equal '',         cell_text(row, 8)

    assert row.css('.approval .rwa-user a.user').text.include?('Dave Lopper')
    assert_equal 'Rejected', row.css('.approval .rwa-status').text.strip
    assert_equal 'test rejected', row.css('.rwa-note').text.strip

    # --- Version 5 (row 1) ---
    row = rows[1]
    assert_equal 'Released', cell_text(row, 6)
    assert_equal '1',        cell_text(row, 7)
    assert_equal '1',        cell_text(row, 8)

    assert_equal 'Approved', row.css('.approval .rwa-status').text.strip
    assert_equal 'test approved', row.css('.rwa-note').text.strip

    # --- Version 4 (row 2) ---
    row = rows[2]
    assert_equal 'Canceled', cell_text(row, 6)
    assert_equal '1',        cell_text(row, 7)
    assert_equal '',         cell_text(row, 8)

    assert_equal 'Canceled', row.css('.approval .rwa-status').text.strip
    assert_equal 'test pending', row.css('.rwa-note').text.strip

    # --- Version <= 3: keine Approval-Details ---
    rows[3..].each_with_index do |row, i|
      assert row.css('.approval ul li').empty?,
            "No approval expected in old version row #{i + 3}"
    end
  end

  test 'wiki history approval with workflow page 1 first published then same content pending' do
    @page = WikiPage.find(1)
    @page.content.text = "content text"
    @page.content.author = @admin
    @page.content.save!
    approval = WikiApprovalWorkflow.create!(
      page_id: @page.id,
      version: @page.content.version,
      status: :published,
      author_id: @admin.id
    )

    approval.status = :pending
    approval.save!

    step = approval.approval_steps.for_principal(@dlopper).find_or_initialize_by(step: 1)
    step.step_status = :pending
    step.note = "test pending"
    step.save!

    get :history, params: { project_id: @project.id, id: @page.title, page: 1, per_page: 25 }

    assert_response :success
    rows = css_select('tbody tr.wiki-page-version')

    first_row = rows.first

    assert_select first_row, 'td', text: 'In approval'

    revision_cell = first_row.css('td')[8] # 0-indexed, Revision ist die 9. Spalte
    assert_equal '', revision_cell.text.strip,
      'Revision should be empty when workflow was restarted from published to pending'

    assert_select first_row, 'td .approval ul li .rwa-user a', text: 'Redmine Admin'

    assert_select first_row, 'td .approval .rwa-status', text: /In approval/
    assert_select first_row, 'td .approval .rwa-note', text: 'test pending'
  end
end
