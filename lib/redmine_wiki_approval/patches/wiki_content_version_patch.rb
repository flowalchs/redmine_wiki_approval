# frozen_string_literal: true

module RedmineWikiApproval
  module Patches
    module WikiContentVersionPatch
      extend ActiveSupport::Concern

      included do
        has_many :wiki_approval_workflows,
                class_name: 'WikiApprovalWorkflow',
                foreign_key: :version, # Column in our Table
                primary_key: :version, # Column in Redmine where is the versionNr
                dependent: :destroy
      end
    end
  end
end
