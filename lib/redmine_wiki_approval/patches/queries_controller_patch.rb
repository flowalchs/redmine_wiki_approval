# frozen_string_literal: true

module RedmineWikiApproval
  module Patches
    module QueriesControllerPatch
      extend ActiveSupport::Concern

      included do
        prepend InstanceOverwriteMethods
      end

      module InstanceOverwriteMethods
        private

        def redirect_to_wiki_approval_query(options)
          if @project
            redirect_to wiki_approval_project_index_path(
              project_id: @project,
              **options
            )
          else
            redirect_to wiki_approval_index_path(**options)
          end
        end
      end
    end
  end
end
