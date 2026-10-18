# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class WikiApprovalQueryApiTest < WikiApproval::Test::IntegrationCase
  def setup
    super
    Setting.rest_api_enabled = '1'
    @jsmith_header = credentials('jsmith')
  end

  def test_index_returns_pagination_meta
    get "/projects/#{@project.id}/wiki_approval.json", params: { offset: 2, limit: 3, sort: 'title' }, headers: @jsmith_header
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal 8, json['total_count']
    assert_equal 2, json['offset']
    assert_equal 3, json['limit']
    assert_equal 3, json['wiki_pages'].size

    titles = WikiPage.where(wiki_id: @project.wiki.id).order(:title).pluck(:title)
    assert_equal titles[2, 3], json['wiki_pages'].map { |p| p['title'] }
  end

  def test_index_with_filter
    get "/projects/#{@project.id}/wiki_approval.json",
        params: { set_filter: 1, f: ['step_status'], op: { step_status: '=' }, v: { step_status: ['pending'] } },
        headers: @jsmith_header
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal 1, json['total_count']
    assert_equal 'Page_with_sections', json['wiki_pages'].first['title']
    assert_equal 'pending', json['wiki_pages'].first['wiki_approval_workflow']['status']
  end

  def test_index_with_invalid_filter_returns_errors
    get "/projects/#{@project.id}/wiki_approval.json",
        params: { set_filter: 1, f: ['created_on'], op: { created_on: '>t-' }, v: { created_on: ['abc'] } },
        headers: @jsmith_header
    assert_response :unprocessable_entity
  end
end
