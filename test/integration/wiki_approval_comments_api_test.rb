# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class WikiApprovalCommentsApiTest < WikiApproval::Test::IntegrationCase
  def setup
    super
    Setting.rest_api_enabled = '1'
    [@manager_role, @developer_role].each do |role|
      role.add_permission! :wiki_comments_view
      role.add_permission! :wiki_comments_add
    end
    @page = WikiPage.find(11)
    @base = "/projects/#{@project.id}/wiki_approval/#{@page.title}/comments"
  end

  test 'list comments with replies' do
    thread = WikiApprovalComment.create!(page_id: @page.id, author: @jsmith, text: 'Thread', quote: 'Section', version: 2)
    WikiApprovalComment.create!(page_id: @page.id, author: @dlopper, text: 'Reply', parent: thread)

    get "#{@base}.json", headers: credentials('jsmith')
    assert_response :success

    comment = JSON.parse(response.body)['comments'].first
    assert_equal 'Thread', comment['text']
    assert_equal 'open', comment['status']
    assert_equal 'Section', comment['quote']
    assert_equal 2, comment['version']
    assert_equal 'Reply', comment['replies'].first['text']
  end

  test 'create, resolve and delete comment' do
    post "#{@base}.json", params: { text: 'Via API', quote: 'Section' }, headers: credentials('jsmith')
    assert_response :created
    id = JSON.parse(response.body)['comment']['id']

    put "#{@base}/#{id}/resolve.json", params: { version: 2 }, headers: credentials('jsmith')
    assert_response :success
    assert_equal 'resolved', JSON.parse(response.body)['comment']['status']
    assert_equal 2, JSON.parse(response.body)['comment']['resolved_version']

    delete "#{@base}/#{id}.json", headers: credentials('jsmith')
    assert_response :no_content
    assert_not WikiApprovalComment.exists?(id)
  end

  test 'json body: create, reply, resolve and reopen' do
    json_headers = credentials('jsmith').merge('CONTENT_TYPE' => 'application/json')

    post "#{@base}.json", params: { text: 'Json thread', quote: 'Section', version: 2 }.to_json, headers: json_headers
    assert_response :created
    thread = JSON.parse(response.body)['comment']
    assert_equal 1, thread['number']
    assert_equal 2, thread['version']

    post "#{@base}.json", params: { text: 'Json reply', parent_id: thread['id'] }.to_json, headers: json_headers
    assert_response :created
    assert_equal thread['id'], JSON.parse(response.body)['comment']['parent_id']

    put "#{@base}/#{thread['id']}/resolve.json", params: { resolved: true, version: 2 }.to_json, headers: json_headers
    assert_equal 'resolved', JSON.parse(response.body)['comment']['status']

    put "#{@base}/#{thread['id']}/resolve.json", params: { resolved: false }.to_json, headers: json_headers
    assert_equal 'open', JSON.parse(response.body)['comment']['status']

    get "#{@base}.json?status=open", headers: credentials('jsmith')
    assert_equal ['Json reply'], JSON.parse(response.body)['comments'].first['replies'].map { |r| r['text'] }
  end

  test 'create with invalid data returns validation errors' do
    post "#{@base}.json", params: { text: '' }, headers: credentials('jsmith')
    assert_response :unprocessable_entity
    assert JSON.parse(response.body)['errors'].any?
  end
end
