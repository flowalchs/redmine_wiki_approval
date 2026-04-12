# frozen_string_literal: true

RedmineApp::Application.routes.draw do
  patch 'projects/:project_id/wiki_approval_settings',        to: 'wiki_approval_settings#update', as: 'wiki_approval_settings'
  get   'projects/:project_id/wiki_approval/:title/status',   to: 'wiki_approval#status',          as: 'wiki_approval_status'
  get   'projects/:project_id/wiki_approval/:title/history',  to: 'wiki_approval#history',         as: 'wiki_approval_history'
  put   'projects/:project_id/wiki_approval/:title/start',    to: 'wiki_approval#start',           as: 'wiki_approval_start'
  match 'projects/:project_id/wiki_approval/:title/grant',    to: 'wiki_approval#grant',           as: 'wiki_approval_grant',     via: [:get, :put]
  match 'projects/:project_id/wiki_approval/:title/forward',  to: 'wiki_approval#forward',         as: 'wiki_approval_forward',   via: [:get, :put]
  patch 'projects/:project_id/wiki_approval/:title/publish',  to: 'wiki_approval#publish',         as: 'wiki_approval_publish'
  get   'projects/:project_id/wiki_approval/permissions',     to: 'wiki_approval#permissions',     as: 'wiki_approval_permissions'
  match 'projects/:project_id/wiki_approval',                 to: 'wiki_approval#index',           as: 'wiki_approval_project_index', via: [:get, :post]
  match 'wiki_approval',                                      to: 'wiki_approval#index',           as: 'wiki_approval_index',         via: [:get, :post]
end
