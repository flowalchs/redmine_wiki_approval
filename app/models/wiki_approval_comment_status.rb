# frozen_string_literal: true

# resolve / reopen of a comment thread, for the activity and mail notifications
class WikiApprovalCommentStatus < ApplicationRecord
  self.table_name = 'wiki_approval_comment_statuses'

  belongs_to :comment, class_name: 'WikiApprovalComment'
  belongs_to :author, class_name: 'User'

  validates :status, presence: true
  after_commit :send_notification, on: :create

  acts_as_activity_provider \
    type: 'wiki_approval_comments',
    author_key: :author_id,
    timestamp: "#{table_name}.created_at",
    permission: :wiki_comments_view,
    scope: proc { |_options = {}, _user = nil|
      joins(comment: { wiki_page: { wiki: :project } })
        .includes({ author: [:email_address, :preference] }, comment: { wiki_page: { wiki: :project } })
    }

  acts_as_event \
    title: ->(o) { "#{o.status_label}: #{o.comment&.wiki_page&.title} ##{o.comment&.number}" },
    type: ->(o) { o.resolved? ? 'checked' : 'reload' }, # svg icon
    author: :author,
    description: ->(o) { o.comment&.text },
    datetime: :created_at,
    url: ->(o) { o.comment&.event_url_options || {} }

  def resolved?
    status == WikiApprovalComment.statuses[:resolved]
  end

  def status_label
    I18n.t(resolved? ? :label_wiki_comment_resolved : :label_wiki_comment_reopened)
  end

  def project
    comment&.wiki_page&.wiki&.project
  end

  def event_group
    "wiki_page:#{comment&.page_id}"
  end

  private

  def send_notification
    WikiApprovalMailer.deliver_wiki_comment(comment, resolved? ? :resolved : :reopened, author)
  end
end
