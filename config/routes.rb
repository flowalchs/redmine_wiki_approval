# frozen_string_literal: true

RedmineApp::Application.routes.draw do
  match "projects/:project_id/wiki_approval_settings", to: "wiki_approval_settings#update", via: [:patch, :post], as: "wiki_approval_settings"
  match "projects/:project_id/wiki_approval/:title/:version", to: "wiki_approval#start_approval", via: [:get, :post], as: "wiki_approval_start"
  match 'projects/:project_id/wiki_approval/:title/:version/grant/:step_id', to: 'wiki_approval#grant_approval', via: [:get, :post],  as: 'wiki_approval_grant'
  match 'projects/:project_id/wiki_approval/:title/:version/forward/:step_id', to: 'wiki_approval#forward_approval', via: [:get, :post],  as: 'wiki_approval_forward'

  # REST API endpoints (JSON only)
  # Fixed paths must precede dynamic :title routes
  get  'projects/:project_id/wiki_approval_api/approvers',      to: 'wiki_approval_api#approvers', as: 'wiki_approval_api_approvers'
  get  'projects/:project_id/wiki_approval_api/pending',         to: 'wiki_approval_api#pending',   as: 'wiki_approval_api_pending'
  get  'projects/:project_id/wiki_approval_api/my_tasks',        to: 'wiki_approval_api#my_tasks',  as: 'wiki_approval_api_my_tasks'
  get  'projects/:project_id/wiki_approval_api/statuses',        to: 'wiki_approval_api#statuses',  as: 'wiki_approval_api_statuses'

  put  'projects/:project_id/wiki_approval_api/:title',          to: 'wiki_approval_api#update',    as: 'wiki_approval_api_update'
  post 'projects/:project_id/wiki_approval_api/:title/release',  to: 'wiki_approval_api#release',   as: 'wiki_approval_api_release'
  post 'projects/:project_id/wiki_approval_api/:title/submit',   to: 'wiki_approval_api#submit',    as: 'wiki_approval_api_submit'
  get  'projects/:project_id/wiki_approval_api/:title/status',   to: 'wiki_approval_api#status',    as: 'wiki_approval_api_status'
end
