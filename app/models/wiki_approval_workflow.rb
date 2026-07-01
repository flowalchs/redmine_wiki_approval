# frozen_string_literal: true

class WikiApprovalWorkflow < ApplicationRecord
  self.table_name = 'wiki_approval_workflows'
  attr_accessor :_status_changed_in_txn

  belongs_to :wiki_page, foreign_key: :page_id
  belongs_to :author, class_name: 'User'

  has_many :approval_steps, class_name: 'WikiApprovalWorkflowStep', dependent: :destroy, inverse_of: :approval
  has_many :approval_statuses, class_name: 'WikiApprovalWorkflowStatus', dependent: :destroy

  validates :status, presence: true
  before_validation :set_current_page_id_if_latest, on: :create

  before_save :assign_revision_if_needed
  before_save :ensure_only_one_current_per_page

  after_create :cancel_old_approvals
  after_update :mark_status_changed
  after_destroy :handover_current_marker
  after_destroy :handover_approved_marker
  after_save :update_approved_marker, if: -> { saved_change_to_status? || id_previously_changed? }
  after_commit :on_status_change

  APPROVED_STATUSES = [:published, :released].freeze

  if ActiveRecord::VERSION::MAJOR >= 7
    # Rails 7.x und 8.x → positional arguments
    enum :status, {
      canceled: 5,
      draft: 10,
      pending: 20,
      rejected: 40,
      published: 60,
      released: 70,
    }
  else
    enum status: { # rubocop:disable Rails/EnumSyntax
      canceled: 5,
      draft: 10,
      pending: 20,
      rejected: 40,
      published: 60,
      released: 70,
    }
  end

  scope :by_author, ->(user_id) { where(author_id: user_id) }
  scope :for_wiki, ->(page_id, version_id) {
    where(page_id: page_id, version: version_id)
  }

  def latest_public_version
    wiki_page&.approved_wiki_aw
  end

  def self.latest_public_version_status(page_id, specific_status = nil)
    if specific_status
      where(page_id: page_id, status: statuses[specific_status]).order(id: :desc).first
    else
      WikiPage.find(page_id).approved_wiki_aw
    end
  end

  def self.latest_public_version_nr(page)
    page.approved_wiki_aw&.version || fallback_version_nr(page)
  end

  def self.fallback_version_nr(page)
    draft = where(page_id: page.id, status: statuses[:draft]).order(version: :desc).first
    return nil unless draft

    WikiContentVersion
      .where(wiki_content_id: page.content.id)
      .where("version < ?", draft.version)
      .order(version: :desc)
      .first
      &.version
  end

  def self.latest_public_from_version(page_id, from_version)
    record = where(
      page_id: page_id,
      status: approved_status_values
    )
    .where('version < ?', from_version)
    .order(id: :desc)
    .select(:version)
    .first

    record&.version || 1
  end

  def self.save_for_draft(page:, content:, user:, status:, wiki_approval_data:)
    content.errors.add(:base, "Invalid Page") and return if page.nil? || page.errors.any? || !page.persisted?
    content.errors.add(:base, "Invalid status") and return unless %w[draft published].include?(status)
    content.errors.add(:base, "Permission denied") and return if status == "published" && !RedmineWikiApproval::Settings.approval_publish?(page.project, wiki_approval_data[:setting])

    approval_required = RedmineWikiApproval::WikiApproval.wiki_approval_ui_status_draft(
      page: page,
      approval: wiki_approval_data[:approval],
      setting: wiki_approval_data[:setting]
    )
    content.errors.add(:base, "Approval Required") and return if approval_required[:approval_required] && approval_required[:status] != status

    approval = find_or_initialize_by(
      page_id: page.id,
      version: page.version
    )

    content.errors.add(:base, "Already Released") and return if approval.released?

    approval.status     = status
    approval.author_id ||= user.id
    approval.save!

    true
  end

  def cancel_old_approvals
    # find old workflows with < pending
    old_ids = WikiApprovalWorkflow
            .where(page_id: page_id)
            .where('version < ?', version)
            .where(status: [WikiApprovalWorkflow.statuses[:draft], WikiApprovalWorkflow.statuses[:pending]])
            .pluck(:id)

    return if old_ids.empty?

    ActiveRecord::Base.transaction do
      # old Approvals canceln, no after_update or after_commit with .update_all
      WikiApprovalWorkflow.where(id: old_ids)
                          .update_all(status: WikiApprovalWorkflow.statuses[:canceled])

      # Steps canceln
      WikiApprovalWorkflowStep.where(wiki_approval_workflow_id: old_ids)
                        .where(step_status: WikiApprovalWorkflowStep.step_statuses[:pending])
                        .update_all(step_status: WikiApprovalWorkflowStep.step_statuses[:canceled],
                                    updated_at: Time.current)
    end
  end

  def mark_status_changed
    # one time per transaction
    self._status_changed_in_txn ||= saved_change_to_status?
  end

  def on_status_change
    return unless self._status_changed_in_txn || saved_change_to_status?

    WikiApprovalWorkflowStatus.create!(
      wiki_approval_workflow_id: self.id,
      status: self.class.statuses[status]
    )

    # Steps cancel when status to published
    if published?
      approval_steps
        .where(step_status: [WikiApprovalWorkflowStep.step_statuses[:unstarted], WikiApprovalWorkflowStep.step_statuses[:pending]])
        .update_all(
          step_status: WikiApprovalWorkflowStep.step_statuses[:canceled],
          updated_at: Time.current
        )
    end
  end

  def wiki_version
    wiki_page&.content_for_version(version)
  end

  def self.approved_status_values
    statuses.values_at(*APPROVED_STATUSES.map(&:to_s))
  end

  private

  def assign_revision_if_needed
    # value set when
    # - status published or released
    # - revision is  nil
    unless published? || released?
      self.revision = nil
      return
    end

    return unless self.revision.nil?

    self.revision = next_revision
  end

  def next_revision
    last_rev = self.class
      .where(page_id: page_id, status: self.class.approved_status_values)
      .maximum(:revision)

    (last_rev || 0) + 1
  end

  def ensure_only_one_current_per_page
    if current_page_id.present?
      WikiApprovalWorkflow
        .where(page_id: page_id)
        .where.not(id: id)
        .where.not(current_page_id: nil)
        .update_all(current_page_id: nil)
    end
  end

  def set_current_page_id_if_latest
    latest_version = WikiApprovalWorkflow.where(page_id: page_id).maximum(:version) || 0
    if version.to_i >= latest_version
      self.current_page_id = self.page_id
    end
  end

  def handover_current_marker
    if current_page_id.present?
      # find new current_page_id, when it was destroyed
      next_leader = WikiApprovalWorkflow
                      .where(page_id: page_id)
                      .order(version: :desc)
                      .first
      next_leader.update_columns(current_page_id: page_id) if next_leader
    end
  end

  def update_approved_marker
    if status.to_sym.in?(APPROVED_STATUSES)
      # Dieser Eintrag ist jetzt ggf. der neueste approved → setzen
      current_approved = WikiApprovalWorkflow
                           .where(page_id: page_id, status: self.class.statuses.values_at(*APPROVED_STATUSES.map(&:to_s)))
                           .order(id: :desc)
                           .first

      if current_approved
        # Alten Marker löschen, neuen setzen
        WikiApprovalWorkflow
          .where(page_id: page_id)
          .where.not(id: current_approved.id)
          .where.not(approved_page_id: nil)
          .update_all(approved_page_id: nil)

        current_approved.update_columns(approved_page_id: page_id) unless current_approved.approved_page_id == page_id
      end
    elsif approved_page_id.present?
      # Status wurde weg von approved geändert → Marker ggf. wandern
      WikiApprovalWorkflow
            .where(page_id: page_id)
            .where.not(approved_page_id: nil)
            .update_all(approved_page_id: nil)

      new_approved = WikiApprovalWorkflow
                       .where(page_id: page_id, status: self.class.statuses.values_at(*APPROVED_STATUSES.map(&:to_s)))
                       .order(id: :desc)
                       .first
      new_approved&.update_columns(approved_page_id: page_id)
    end
  end

  def handover_approved_marker
    return unless approved_page_id.present?

    WikiApprovalWorkflow
      .where(page_id: page_id, status: self.class.statuses.values_at(*APPROVED_STATUSES.map(&:to_s)))
      .where.not(id: id)
      .order(id: :desc)
      .first
      &.update_columns(approved_page_id: page_id)
  end
end
