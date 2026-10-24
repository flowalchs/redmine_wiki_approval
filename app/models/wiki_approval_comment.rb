# frozen_string_literal: true

class WikiApprovalComment < ApplicationRecord
  self.table_name = 'wiki_approval_comments'

  ANCHOR_CONTEXT_LENGTH = 64
  QUOTE_MAX_LENGTH = 2000

  belongs_to :wiki_page, foreign_key: :page_id
  belongs_to :author, class_name: 'User'
  belongs_to :resolved_by, class_name: 'User', optional: true
  belongs_to :parent, class_name: 'WikiApprovalComment', optional: true, inverse_of: :replies

  has_many :replies, -> { order(:created_at, :id) },
           class_name: 'WikiApprovalComment', foreign_key: :parent_id,
           dependent: :delete_all, inverse_of: :parent
  has_many :status_changes, class_name: 'WikiApprovalCommentStatus', foreign_key: :comment_id,
           dependent: :delete_all

  enum :status, { open: 0, resolved: 1 }

  validates :text, presence: true
  validates :quote, length: { maximum: QUOTE_MAX_LENGTH }
  validate :validate_parent

  before_validation :normalize_anchor
  before_create :assign_number
  after_commit :send_notification, on: :create

  acts_as_activity_provider \
    type: 'wiki_approval_comments',
    author_key: :author_id,
    timestamp: "#{table_name}.created_at",
    permission: :wiki_comments_view,
    scope: proc { |_options = {}, _user = nil|
      joins(wiki_page: { wiki: :project })
        .includes({ author: [:email_address, :preference] }, wiki_page: { wiki: :project })
    }

  acts_as_event \
    title: ->(o) { "#{I18n.t(:label_wiki_comment)}: #{o.wiki_page&.title} ##{o.number}" },
    type: 'comment', # svg icon
    author: :author,
    description: :text,
    datetime: :created_at,
    url: ->(o) { o.event_url_options }

  scope :threads, -> { where(parent_id: nil) }
  scope :for_page, ->(page) { where(page_id: page.id) }

  def thread?
    parent_id.nil?
  end

  def inline?
    quote.present?
  end

  def editable_by?(user, project)
    return false unless user.logged?

    user.allowed_to?(:wiki_comments_manage, project) ||
      (author_id == user.id && user.allowed_to?(:wiki_comments_add, project))
  end

  def resolvable_by?(user, project)
    thread? && user.logged? &&
      (user.allowed_to?(:wiki_comments_add, project) || user.allowed_to?(:wiki_comments_manage, project))
  end

  # status as it was in a page version: resolved only if resolved in or before it
  def status_at(version)
    return status if version.nil? || open?

    resolved_version.nil? || resolved_version <= version ? 'resolved' : 'open'
  end

  # resolved threads of a version: resolved in it ('current') or before ('earlier')
  def resolved_group(version)
    return nil unless status_at(version) == 'resolved'

    resolved_version == version ? 'current' : 'earlier'
  end

  def resolve!(user, version)
    transaction do
      update!(status: :resolved, resolved_by: user, resolved_version: version, resolved_at: Time.now)
      status_changes.create!(author: user, status: self.class.statuses[:resolved], version: version)
    end
  end

  def reopen!(user, version)
    transaction do
      update!(status: :open, resolved_by: nil, resolved_version: nil, resolved_at: nil)
      status_changes.create!(author: user, status: self.class.statuses[:open], version: version)
    end
  end

  def project
    wiki_page&.wiki&.project
  end

  def event_group
    "wiki_page:#{page_id}"
  end

  # link to the comment on the wiki page (#comment-<number>)
  def event_url_options
    { controller: 'wiki', action: 'show', project_id: project, id: wiki_page&.title, anchor: "comment-#{number}" }
  end

  # threads with replies and users, open threads first
  def self.threads_for(page)
    threads.for_page(page)
           .includes(:author, :resolved_by, replies: :author)
           .order(:status, :created_at, :id)
  end

  # threads of a page version (started in or before it) with the status at that version,
  # summary { open:, resolved:, resolved_current:, resolved_earlier:, authors: [[user, open_count], ...] }
  # and the number of newer threads
  # threads are ordered by creation time, newest first with reverse (user preference like issue notes)
  def self.version_data(page, version, reverse: false)
    scope = threads.for_page(page)
    visible = scope.where('version IS NULL OR version <= ?', version)
                   .includes(:author, :resolved_by, replies: :author)
                   .order(:created_at, :id).to_a
    visible.reverse! if reverse
    open, resolved = visible.partition { |t| t.status_at(version) == 'open' }
    current, earlier = resolved.partition { |t| t.resolved_group(version) == 'current' }

    {
      threads: visible,
      summary: {
        open: open.size,
        resolved: resolved.size,
        resolved_current: current.size,
        resolved_earlier: earlier.size,
        authors: open.group_by(&:author).map { |user, list| [user, list.size] }.sort_by { |_, n| -n }
      },
      newer: scope.where('version > ?', version).count
    }
  end

  private

  def send_notification
    WikiApprovalMailer.deliver_wiki_comment(self, :added, author)
  end

  # running number per wiki page, starting at 1 (links use the id, so a number
  # reused after deleting the last comment never points to another comment)
  def assign_number
    self.number = (self.class.where(page_id: page_id).maximum(:number) || 0) + 1
  end

  def normalize_anchor
    self.quote = nil if quote.blank? || !thread?
    if quote.nil?
      self.prefix = nil
      self.suffix = nil
    else
      # form submits send CRLF, the page text only has LF
      self.quote = quote.gsub("\r\n", "\n")
      self.prefix = prefix.to_s.gsub("\r\n", "\n").last(ANCHOR_CONTEXT_LENGTH)
      self.suffix = suffix.to_s.gsub("\r\n", "\n").first(ANCHOR_CONTEXT_LENGTH)
    end
  end

  def validate_parent
    return if parent.nil?

    errors.add(:parent_id, :invalid) if parent.parent_id.present? || parent.page_id != page_id
  end
end
