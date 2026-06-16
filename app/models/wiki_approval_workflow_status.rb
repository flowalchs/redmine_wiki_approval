# frozen_string_literal: true

class WikiApprovalWorkflowStatus < ApplicationRecord
  self.table_name = 'wiki_approval_workflow_statuses'

  belongs_to :wiki_approval_workflow
  belongs_to :author, class_name: 'User'

  validates :status, presence: true
  before_validation :set_default_author, on: :create
  after_commit :send_status_change_mail, on: :create

  acts_as_activity_provider \
    type: 'wiki_approval_workflow',
    author_key: :author_id,
    timestamp: "#{table_name}.created_at",
    permission: :wiki_draft_view,
    scope: proc { |options = {}, _user = nil|
      joins(wiki_approval_workflow: { wiki_page: { wiki: :project } })
        .includes({ author: [:email_address, :preference] }, wiki_approval_workflow: { wiki_page: { wiki: :project } })
    }

  acts_as_event \
    title: ->(o) { "Wiki-#{I18n.t(:label_wiki_approval_workflow, default: 'Approval workflow')}: #{o.wiki_approval_workflow&.wiki_page&.title} (##{o.wiki_approval_workflow&.version})" },
    type: 'workflows', # svg icon
    author:      :author,
    description: ->(o) { I18n.t("wiki_approval_workflow.status.#{WikiApprovalWorkflow.statuses.invert[o.status]}", default: o.status) },
    datetime:    :created_at,
    url: ->(o) do
      {
        controller:  'wiki',
        action:      'show',
        project_id:  o.wiki_approval_workflow&.wiki_page&.wiki&.project,
        id:          o.wiki_approval_workflow&.wiki_page&.title,
        version:     o.wiki_approval_workflow&.version
      }.compact
    end

  def project
    wiki_approval_workflow&.wiki_page&.wiki&.project
  end

  def event_group
    "wiki_page:#{wiki_approval_workflow&.page_id}"
  end

  def send_status_change_mail
    return unless status >= WikiApprovalWorkflow.statuses[:pending]

    WikiApprovalMailer.deliver_wiki_approval_state(self.wiki_approval_workflow, self.wiki_approval_workflow.status, self.wiki_approval_workflow.wiki_page, self.author)
  end

  private

  def set_default_author
    self.author ||= User.current
  end
end
