# frozen_string_literal: true

class WikiApprovalWorkflowSteps < ApplicationRecord
  self.table_name = 'wiki_approval_workflow_steps'

  belongs_to :approval, class_name: 'WikiApprovalWorkflow', foreign_key: :wiki_approval_workflow_id,
             inverse_of: :approval_steps

  belongs_to :principal, polymorphic: true

  validates :step, :step_type, :step_status, presence: true
  validates :note, length: { maximum: 1000 }
  validates :note, presence: true, if: :step_status_rejected?

  after_save :check_next_step

  if ActiveRecord::VERSION::MAJOR >= 7
    # Rails 7.x und 8.x → positional arguments
    enum :step_status, {
      unstarted: 15,  # planed for
      pending: 20,    # in approval mode
      rejected: 40,   # no approved
      approved: 70,   # released
      canceled: 90,   # one is rejected, all other canceled
    }, prefix: :step_status

    enum :step_type, {
      or: 0,
      and: 1
    }, prefix: true
  else
    # redmine 5.1
    enum step_status: { # rubocop:disable Rails/EnumSyntax
      unstarted: 15,  # planed for
      pending: 20,    # in approval mode
      rejected: 40,   # no approved
      approved: 70,   # released
      canceled: 90,   # one is rejected, all other canceled
    }, _prefix: true

    enum step_type: { # rubocop:disable Rails/EnumSyntax
      or: 0,
      and: 1
    }, _prefix: true
  end

  scope :for_principal, ->(principal) {
    where(principal_id: principal.id, principal_type: principal.class.name)
  }

  def principal=(obj)
    super
    self.principal_type = obj.class.name if obj
  end

  # Find the first step number for a given approval where:
  # - The principal is the given user OR one of their groups
  # - The step_status is pending
  # - Returns the smallest step number (or nil if none found)
  def self.first_pending_step_for(approval, user, project, id = nil)
    return nil if approval.blank?

    # Build base query for approval steps
    query = approval.approval_steps.where(step_status: step_statuses[:pending])
    query = query.where(id: id) if id.present? # Filter by step if provided

    # 1. Check for steps assigned directly to the user
    step_found = query.where(principal_id: user.id, principal_type: 'User')
                         .order(:id)
                         .first
    return step_found if step_found.present?

    # 2. If no user step found, check for steps assigned to any of the user's groups
    group_ids = user.groups.pluck(:id)
    return nil if group_ids.empty?

    query.where(principal_id: group_ids, principal_type: 'Group')
         .order(:step)
         .first
  end

  def self.check_all_steps_approved(approval)
    # when all steps ar approved or canceld = done
    unless approval.approval_steps.where('step_status < ?', WikiApprovalWorkflowSteps.step_statuses[:approved]).exists?
      approval.update!(status: :released)
    end
  end

  private

  def check_next_step
    case step_status.to_sym
    when :unstarted
      # current stepNr 1 - to pending
      update!(step_status: :pending) if step == find_current_step_for_pending
      current_step_or_is_approved
      approval.update!(status: :pending) unless approval.pending?
    when :pending
      approval.update!(status: :pending) unless approval.pending?
    when :rejected
      # all current to canceled
      approval.approval_steps.where(step_status: :pending).find_each do |step|
        step.update!(step_status: :canceled)
      end
      approval.update!(status: :rejected) unless approval.rejected?
    when :approved

      current_step_or_is_approved

      # start next step if all approved from current step
      unless approval.approval_steps.where(step: step).where('step_status < ?', WikiApprovalWorkflowSteps.step_statuses[:approved]).exists?
        affected = approval.approval_steps.where(step: step + 1).update_all(step_status: :pending, updated_at: Time.current)
        WikiApprovalMailer.deliver_wiki_approval_step(approval, approval.wiki_page, User.current, step + 1) if affected.positive?
      end

      approval.approval_steps.check_all_steps_approved(approval)

    end
  end

  def find_current_step_for_pending
    WikiApprovalWorkflowSteps
      .where(wiki_approval_workflow_id: wiki_approval_workflow_id)
      .where('step_status <= ?', WikiApprovalWorkflowSteps.step_statuses[:pending])
      .where('step <= ?', step)
      .order(step: :asc)
      .limit(1)
      .pluck(:step)
      .first
  end

  def current_step_or_is_approved
    # OR-Logic: delete all <= pending from same stepNr
    return unless step_type_or? && (
      step_status_approved? ||
      approval.approval_steps.where(step: step, step_status: :approved).exists?
    )

    # to status canceled
    approval.approval_steps
            .where(step: step)
            .where('step_status <= ?', WikiApprovalWorkflowSteps.step_statuses[:pending])
            .update_all(step_status: :canceled)
  end
end
