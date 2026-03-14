# frozen_string_literal: true

loader = RedminePluginKit::Loader.new plugin_id: 'redmine_wiki_approval'

Redmine::Plugin.register :redmine_wiki_approval do
  name 'Redmine Wiki Approval Workflow plugin'
  author 'Florian Walchshofer'
  author_url 'https://github.com/FloWalchs/'
  description 'A Redmine plugin that adds an approval workflow to the wiki, including drafts to ensure content quality before publication.'
  url 'https://github.com/FloWalchs/redmine_wiki_approval/'
  version RedmineWikiApproval::VERSION
  requires_redmine :version_or_higher => '4.0.0'

  settings default: loader.default_settings,
           partial: 'settings/wiki_approval'

  project_module :wiki_approval do
    permission :wiki_approval_settings, { :wiki_approval_settings => [:show, :update] }
    permission :wiki_approval_start, { :wiki_approval => [:start_approval],
                                       :wiki_approval_api => [:submit, :approvers] }, require: :member
    permission :wiki_approval_grant, { :wiki_approval => [:grant_approval],
                                       :wiki_approval_api => [:release, :pending, :my_tasks] }, require: :member
    permission :wiki_approval_forward, { :wiki_approval => [:forward_approval] }, require: :member
    permission :wiki_draft_view, { :wiki_approval => [:view_draft],
                                   :wiki_approval_api => [:status, :statuses] }, require: :member
    permission :wiki_draft_create, { :wiki_approval => [:set_draft],
                                     :wiki_approval_api => [:update] }, require: :member
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
  Redmine::Notifiable.singleton_class.prepend RedmineWikiApproval::Patches::NotifiablePatch

  # Hooks
  loader.load_model_hooks!
end
