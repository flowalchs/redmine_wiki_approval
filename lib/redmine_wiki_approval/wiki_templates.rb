# frozen_string_literal: true

module RedmineWikiApproval
  class WikiTemplates
    GLOBAL    = 'global'
    PROJECTS  = 'projects'
    ROLES     = 'roles'
    TEMPLATES = 'templates'

    SECTION_MAP = {
      GLOBAL    => ['Global', 'global', 'Globals', 'globals', 'GLOBAL'],
      PROJECTS  => ['Projects', 'projects', 'Project', 'project', 'PROJECTS'],
      ROLES     => ['Roles', 'roles', 'Role', 'role', 'ROLES'],
      TEMPLATES => ['Templates', 'templates', 'Template', 'template', 'TEMPLATES']
    }.freeze

    ENABLED_TEMPLATE_TYPES = [GLOBAL, PROJECTS, ROLES].freeze

    attr_reader :project, :user, :setting

    def initialize(project:, user:, setting:)
      @project = project
      @user = user
      @setting = setting
    end

    def templates
      return nil unless valid_setting?

      format_templates(collect_templates)
    end

    def template?(page:)
      !template_type_for_cached(page).nil?
    end

    def user_can_edit_template?(page:)
      return false unless template_type_for_cached(page)

      user.allowed_to?(:wiki_template_edit, project)
    end

    def accessible_template?(page:)
      typ = template_type_for_cached(page)
      return false unless typ
      return false unless valid_setting?(typ)
      return false unless user_has_role_for_template?(typ, page)

      true
    end

    private

    def template_type_for_cached(page)
      return nil unless valid_setting?

      @template_type_cache ||= {}
      @template_type_cache[page.id] ||= template_type_for(page)
    end

    def valid_setting?(typ = nil)
      enabled = enabled_templates
      return false if enabled.blank?

      if typ
        return false unless ENABLED_TEMPLATE_TYPES.include?(typ.to_s)

        enabled.include?(typ.to_s)
      else
        enabled.any?
      end
    end

    def enabled_templates
      @enabled_templates ||= RedmineWikiApproval::Settings.wiki_templates(project, setting)
    end

    def template_type_for(page)
      path = template_path_cached(page)
      return nil if path.empty?
      return nil unless in_section_map?(TEMPLATES, path.first.title)
      # Templates root
      return GLOBAL if path.length == 1

      titles = path.map { |p| p.title.to_s.downcase }

      # Templates → Global → names
      if in_section_map?(GLOBAL, titles[1])
        return nil if path.length > 3

        return GLOBAL
      end

      if in_section_map?(PROJECTS, titles[1])
        return PROJECTS if path.length == 2
        return nil unless Project.find_by(identifier: titles[2].to_s.downcase)

        # Templates → Projects → identifier → template
        return PROJECTS if path.length == 3 || path.length == 4

        # Templates → Projects → identifier → Roles → role → template
        if path.length <= 6 && SECTION_MAP[ROLES].any? { |r| titles[3].start_with?(r.downcase) }
          # length 5: Templates → Projects → identifier → Roles → rollename
          return PROJECTS if path.length == 5

          role_title = titles[4].to_s
          roles = Role.pluck(:name).map(&:downcase)
          return PROJECTS if roles.any? { |r| role_title.start_with?(r) }
        end
      end

      # Templates → Roles → role → template
      if in_section_map?(ROLES, titles[1])
        return nil if path.length > 4
        return ROLES if path.length == 2

        roles ||= Role.pluck(:name).map(&:downcase)
        role_title = titles[2].to_s
        return ROLES if roles.include?(role_title)
      end

      nil
    end

    def template_path(page)
      path = []
      current = page
      depth = 0

      while current && depth <= 6
        path << current
        return path.reverse if in_section_map?(TEMPLATES, current.title)

        current = current.parent
        depth += 1
      end
      []
    end

    def collect_templates
      enabled = enabled_templates
      return nil unless enabled.any?

      section_titles = enabled.flat_map { |e| SECTION_MAP[e] || [] }
      # case options for wiki title
      roles      = user.roles_for_project(project).pluck(:name).flat_map { |r| case_variants(r) } if enabled.include?(ROLES) || enabled.include?(PROJECTS)
      identifier = case_variants(project.identifier) if enabled.include?(PROJECTS)
      templates, project_roles, global_roles = [], [], []

      # Templates Roots (all Wikis) enabled modul
      WikiPage.includes(wiki: { project: :enabled_modules }).joins(wiki: :project)
              .where(parent_id: nil, title: SECTION_MAP[TEMPLATES])
              .where(projects: { status: Project::STATUS_ACTIVE })
              .select { |p| p.wiki.project.module_enabled?(:wiki_approval) }
              .each do |root|
        # Section_ids enabled
        section_ids = WikiPage.where(wiki_id: root.wiki_id, parent_id: root.id, title: section_titles)
                              .pluck(:title, :id)
                              .to_h
        # GLOBAL
        if (global_id = find_section_id(section_ids, GLOBAL))
          templates += WikiPage.where(parent_id: global_id).to_a
        end
        # PROJECT
        if (projects_id = find_section_id(section_ids, PROJECTS))
          project_children = WikiPage.where(parent_id: WikiPage.where(parent_id: projects_id, title: identifier).select(:id)).to_a

          # roles inside project found
          project_roles_section = project_children.find do |p|
            SECTION_MAP[ROLES].any? { |r| p.title.to_s.start_with?(r) }
          end
          templates += project_children.reject { |p| p == project_roles_section }

          # Project Roles like
          if project_roles_section && roles && roles.any?
            role_pages = WikiPage.where(parent_id: project_roles_section.id)
                                 .where(roles.map { "title LIKE ?" }.join(" OR "), *roles.map { |r| "#{r}%" })
            project_roles += WikiPage.where(parent_id: role_pages.select(:id)).to_a
          end
        end
        # ROLES
        if (roles_id = find_section_id(section_ids, ROLES)) && roles && roles.any? && project_roles.empty?
          global_roles += WikiPage.where(parent_id: WikiPage.where(parent_id: roles_id, title: roles).select(:id)).to_a
        end
      end

      # title + approvalId
      templates + (project_roles.any? ? project_roles : global_roles)
    end

    def template_path_cached(page)
      @template_path_cache ||= {}
      @template_path_cache[page.id] ||= template_path(page)
    end

    def user_has_role_for_template?(typ, page)
      return true unless typ == ROLES || typ == PROJECTS

      path = template_path_cached(page)
      titles = path.map { |p| p.title.to_s.downcase }

      role_title = in_section_map?(PROJECTS, titles[1]) ? titles[4] : titles[2]
      return true if role_title.blank?

      user_roles = user.roles_for_project(project).map(&:name).map(&:downcase)
      user_roles.any? { |r| role_title.start_with?(r) }
    end

    def format_templates(templates)
      templates.uniq(&:id).filter_map do |t|
        id = WikiApprovalWorkflow.latest_public_version_status(t.id)&.id
        id ? [t.pretty_title, id] : nil
      end.presence
    end

    def in_section_map?(map, value)
      SECTION_MAP[map].map(&:downcase).include?(value.to_s.downcase)
    end

    def case_variants(str)
      [str, str.capitalize, str.titleize, str.downcase, str.upcase].uniq
    end

    def find_section_id(section_ids, key)
      SECTION_MAP[key].find { |variant| section_ids[variant] }
        &.then { |v| section_ids[v] }
    end
  end
end
