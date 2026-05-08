# frozen_string_literal: true

module RedmineWikiApproval
  module WikiMacros
    module UsersMacro
      Redmine::WikiFormatting::Macros.register do
        desc <<~DESCRIPTION
          Displays the wiki approval users for the current workflow.

          {{rwa_users}}
          {{rwa_users(userimage,step=1,approved)}}
          {{rwa_users(starter,step=0,note,userimage)}}

          Boolean parameters can be passed either as flags (e.g. "starter")
          or explicitly using "=true" or "=false".

          Parameters:
          - starter: true|false
            Show the workflow starter (default: false)
          - step: NUMBER
            Filter by approval step number (optional)
          - note: true|false
            Show approval notes (default: false)
          - userimage: true|false
            Show user avatars (default: false)
          - status: true|false
            Show step status (default: false)
          - mouseover: true|false
            Enable mouse-over tooltips (default: false)
          - userlink: true|false
            Render user name as link (default: false) 
          - approved: true|false
            Show only approved steps (default: false)
        DESCRIPTION
        macro :rwa_users do |obj, args|
          approval = @wiki_approval_data&.dig(:approval)
          return '' unless approval

          # --- parse named parameters ---
          options = args.each_with_object({}) do |arg, hash|
            key, value = arg.split('=', 2)
            hash[key.to_sym] =
              if value.nil?
                true
              else
                case value
                when 'true'  then true
                when 'false' then false
                else value
                end
              end
          end

          wiki_approval_users(
            approval,
            starter:   options.fetch(:starter, false),
            step:      options.fetch(:step, nil),
            note:      options.fetch(:note, false),
            userimage: options.fetch(:userimage, false),
            status:    options.fetch(:status, false),
            mouseover: options.fetch(:mouseover, false),
            userlink:  options.fetch(:userlink, false),
            approved:  options.fetch(:approved, false)
          )
        end
      end
    end
  end
end
