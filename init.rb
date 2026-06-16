# frozen_string_literal: true

loader = RedminePluginKit::Loader.new plugin_id: 'redmine_wiki_approval'

Redmine::Plugin.register :redmine_wiki_approval do
  name 'Redmine Wiki Approval Workflow plugin'
  author 'Florian Walchshofer'
  author_url 'https://github.com/flowalchs/'
  description 'A Redmine plugin that adds an approval workflow to the wiki, including drafts to ensure content quality before publication.'
  url 'https://github.com/flowalchs/redmine_wiki_approval/'
  version RedmineWikiApproval::VERSION
  requires_redmine :version_or_higher => '4.0.0'

  settings default: loader.default_settings,
           partial: 'settings/wiki_approval'

  project_module :wiki_approval do
    permission :wiki_approval_settings, { :wiki_approval_settings => [:update],
                                          :wiki_approval => [:permissions] }, require: :member
    permission :wiki_approval_start, { :wiki_approval => [:start] }, require: :member
    permission :wiki_approval_grant, { :wiki_approval => [:grant] }, require: :member
    permission :wiki_approval_forward, { :wiki_approval => [:forward] }, require: :member
    permission :wiki_draft_view, { :wiki_approval => [:status, :history, :index] }, require: :member
    permission :wiki_approval_publish, { :wiki_approval => [:publish] }, require: :member
    permission :wiki_template_edit, {}, require: :member
  end

  menu :admin_menu,
      :redmine_wiki_approval,
      { controller: 'settings', action: 'plugin', id: 'redmine_wiki_approval' },
      caption: :label_wiki_approval,
      icon: 'wiki-page',
      html: { class: 'icon icon-wiki-page' }

  activity_provider :wiki_approval_workflow, :class_name => 'WikiApprovalWorkflowStatus', :default => false
end

RedminePluginKit::Loader.persisting do
  # Hooks
  loader.load_model_hooks!
end
