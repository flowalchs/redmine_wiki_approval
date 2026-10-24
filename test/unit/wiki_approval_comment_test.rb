# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class WikiApprovalCommentTest < WikiApproval::Test::UnitCase
  def setup
    super
    @page = WikiPage.find(11)
    @manager_role.add_permission! :wiki_comments_add
    @developer_role.add_permission! :wiki_comments_add
  end

  def create_thread(attrs = {})
    WikiApprovalComment.create!({ page_id: @page.id, author: @jsmith, text: 'Thread', version: 2 }.merge(attrs))
  end

  test 'page comment without quote has no anchor' do
    comment = create_thread(prefix: 'abc', suffix: 'def')

    assert comment.thread?
    assert_not comment.inline?
    assert_nil comment.prefix
    assert_nil comment.suffix
    assert comment.open?
  end

  test 'inline comment truncates anchor context' do
    comment = create_thread(quote: 'section', prefix: 'a' * 100, suffix: 'b' * 100)

    assert comment.inline?
    assert_equal WikiApprovalComment::ANCHOR_CONTEXT_LENGTH, comment.prefix.length
    assert_equal WikiApprovalComment::ANCHOR_CONTEXT_LENGTH, comment.suffix.length
  end

  test 'replies are not anchored and cannot be nested' do
    thread = create_thread(quote: 'section')
    reply = WikiApprovalComment.create!(page_id: @page.id, author: @dlopper, text: 'Reply', parent: thread, quote: 'x')

    assert_nil reply.quote
    assert_equal [reply], thread.replies.to_a

    nested = WikiApprovalComment.new(page_id: @page.id, author: @dlopper, text: 'Nested', parent: reply)
    assert_not nested.valid?
  end

  test 'numbers start at 1 per page and keep gaps' do
    first = create_thread
    reply = WikiApprovalComment.create!(page_id: @page.id, author: @dlopper, text: 'Reply', parent: first)
    last = create_thread
    other_page = WikiApprovalComment.create!(page_id: 1, author: @jsmith, text: 'Other page')

    assert_equal [1, 2, 3], [first.number, reply.number, last.number]
    assert_equal 1, other_page.number

    reply.destroy
    assert_equal 4, create_thread.number
  end

  test 'anchor line breaks are normalized' do
    comment = create_thread(quote: "line one\r\nline two", prefix: "a\r\n", suffix: "\r\nb")

    assert_equal "line one\nline two", comment.quote
    assert_equal "a\n", comment.prefix
    assert_equal "\nb", comment.suffix
  end

  test 'text is required' do
    assert_not WikiApprovalComment.new(page_id: @page.id, author: @jsmith, text: '').valid?
  end

  test 'resolve and reopen store version and user' do
    thread = create_thread
    thread.resolve!(@dlopper, 3)

    assert thread.reload.resolved?
    assert_equal 3, thread.resolved_version
    assert_equal @dlopper, thread.resolved_by
    assert_not_nil thread.resolved_at

    thread.reopen!(@jsmith, 3)
    assert thread.reload.open?
    assert_nil thread.resolved_version
    assert_nil thread.resolved_by
  end

  test 'version data counts threads and open authors' do
    create_thread
    create_thread(author: @dlopper)
    create_thread(author: @dlopper).resolve!(@jsmith, 3)
    WikiApprovalComment.create!(page_id: @page.id, author: @rhill, text: 'Reply', parent: create_thread)

    data = WikiApprovalComment.version_data(@page, 3)
    assert_equal 3, data[:summary][:open]
    assert_equal 1, data[:summary][:resolved]
    assert_equal [[@jsmith, 2], [@dlopper, 1]], data[:summary][:authors]
    assert_equal 4, data[:threads].size
    assert_equal 0, data[:newer]
  end

  test 'version data shows the state of an older version' do
    old = create_thread(version: 1)
    old.resolve!(@jsmith, 3)
    newer = create_thread(version: 3)

    data = WikiApprovalComment.version_data(@page, 2)
    assert_equal [old], data[:threads]
    assert_equal 1, data[:summary][:open]
    assert_equal 0, data[:summary][:resolved]
    assert_equal 1, data[:newer]

    current = WikiApprovalComment.version_data(@page, 3)
    assert_equal [old, newer], current[:threads]
    assert_equal [newer, old], WikiApprovalComment.version_data(@page, 3, reverse: true)[:threads]
    assert_equal 1, current[:summary][:resolved]
  end

  test 'resolved threads are split into this and earlier revisions' do
    earlier = create_thread(version: 1)
    earlier.resolve!(@jsmith, 2)
    current = create_thread(version: 1)
    current.resolve!(@jsmith, 3)
    open = create_thread(version: 1)

    data = WikiApprovalComment.version_data(@page, 3)
    # by creation time, the resolved tab groups them with css
    assert_equal [earlier, current, open], data[:threads]
    assert_equal 1, data[:summary][:resolved_current]
    assert_equal 1, data[:summary][:resolved_earlier]
    assert_equal 'current', current.resolved_group(3)
    assert_equal 'earlier', earlier.resolved_group(3)
    assert_nil open.resolved_group(3)
  end

  test 'status at a version' do
    thread = create_thread(version: 1)
    assert_equal 'open', thread.status_at(5)

    thread.resolve!(@jsmith, 3)
    assert_equal 'open', thread.status_at(2)
    assert_equal 'resolved', thread.status_at(3)
    assert_equal 'resolved', thread.status_at(4)
    assert_equal 'resolved', thread.status_at(nil)
  end

  test 'editable by author or manager' do
    thread = create_thread(author: @dlopper)

    assert thread.editable_by?(@dlopper, @project)
    assert_not thread.editable_by?(@jsmith, @project)

    @manager_role.add_permission! :wiki_comments_manage
    assert thread.editable_by?(@jsmith.reload, @project)
    assert_not thread.editable_by?(User.anonymous, @project)
  end

  test 'destroying the page removes comments' do
    thread = create_thread
    WikiApprovalComment.create!(page_id: @page.id, author: @dlopper, text: 'Reply', parent: thread)

    @page.destroy
    assert_equal 0, WikiApprovalComment.where(page_id: @page.id).count
  end
end
