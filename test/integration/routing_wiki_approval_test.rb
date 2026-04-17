# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class RoutingWikiTest < Redmine::RoutingTest
  def test_approval
    # Settings
    should_route 'PATCH /projects/foo/wiki_approval_settings' => 'wiki_approval_settings#update',
                 :project_id => 'foo'
    # Status
    should_route 'GET  /projects/foo/wiki_approval/Page_with_sections/status' => 'wiki_approval#status',
                 :project_id => 'foo', :title => 'Page_with_sections'
    # Start approval
    should_route 'PUT /projects/foo/wiki_approval/Page_with_sections/start' => 'wiki_approval#start',
                 :project_id => 'foo', :title => 'Page_with_sections'
    # Grant
    should_route 'GET  /projects/foo/wiki_approval/Page_with_sections/grant' => 'wiki_approval#grant',
                 :project_id => 'foo', :title => 'Page_with_sections'
    should_route 'PUT /projects/foo/wiki_approval/Page_with_sections/grant' => 'wiki_approval#grant',
                 :project_id => 'foo', :title => 'Page_with_sections'
    # Forward
    should_route 'GET  /projects/foo/wiki_approval/Page_with_sections/forward' => 'wiki_approval#forward',
                 :project_id => 'foo', :title => 'Page_with_sections'
    should_route 'PUT /projects/foo/wiki_approval/Page_with_sections/forward' => 'wiki_approval#forward',
                 :project_id => 'foo', :title => 'Page_with_sections'
    # publish
    should_route 'PUT /projects/foo/wiki_approval/Page_with_sections/publish' => 'wiki_approval#publish',
                 :project_id => 'foo', :title => 'Page_with_sections'
    # Permissions
    should_route 'GET  /projects/foo/wiki_approval/permissions' => 'wiki_approval#permissions',
                 :project_id => 'foo'
    # Index
    should_route 'GET  /projects/foo/wiki_approval' => 'wiki_approval#index',
                 :project_id => 'foo'
    should_route 'GET  wiki_approval' => 'wiki_approval#index'
    should_route 'POST  /projects/foo/wiki_approval' => 'wiki_approval#index',
                 :project_id => 'foo'
    should_route 'POST  wiki_approval' => 'wiki_approval#index'
  end
end
