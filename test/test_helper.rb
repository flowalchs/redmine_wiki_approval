# frozen_string_literal: true

if ENV['COVERAGE']
  require 'simplecov'
  require 'simplecov-cobertura'

  SimpleCov.coverage_dir 'coverage'

  SimpleCov.formatters = [
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::CoberturaFormatter
  ]

  SimpleCov.start :rails do
    add_filter 'init.rb'
    root File.expand_path("#{File.dirname __FILE__}/..")
  end

  # Cobertura-XML at the end
  at_exit do
    result = SimpleCov.result
    # Cobertura-file
    SimpleCov::Formatter::CoberturaFormatter.new.format(result)
    # html also
    SimpleCov::Formatter::HTMLFormatter.new.format(result)
  end
end

$VERBOSE = nil if ENV['SUPPRESS_WARNINGS']

# Load the normal Rails helper
require File.expand_path('../../../test/test_helper', __dir__)

PLUGIN_FIXTURES_DIR = File.expand_path('fixtures', __dir__)

module WikiApproval
  module Test
    module PluginTestSetting
      def load_plugin_fixtures_in_order!
        ActiveRecord::FixtureSet.reset_cache
        ActiveRecord::FixtureSet.create_fixtures(
          PLUGIN_FIXTURES_DIR,
          %w[wiki_approval_workflows wiki_approval_workflow_steps wiki_approval_settings wiki_approval_workflow_statuses]
        )
      end

      def load_default_values!
        @admin = User.find_by(login: 'admin')
        @jsmith = User.find_by(login: 'jsmith')
        @dlopper = User.find_by(login: 'dlopper')
        @rhill = User.find_by(login: 'rhill')
        @manager_role = Role.find_by(name: 'Manager')
        @developer_role = Role.find_by(name: 'Developer')
        [@manager_role, @developer_role].each do |role|
          role.add_permission! :wiki_approval_settings
          role.add_permission! :wiki_approval_start
          role.add_permission! :wiki_approval_grant
          role.add_permission! :wiki_approval_forward
          role.add_permission! :wiki_draft_view
          role.add_permission! :wiki_approval_publish
          role.add_permission! :wiki_template_edit
        end
        @project = Project.find 1
        @project2 = Project.find 2
        @project3 = Project.find 3
        [@project, @project3].each do |project|
          project.enable_module! :wiki_approval
        end
        @group = Group.first
      end

      def set_session_user(user)
        @user = user
        @request.session[:user_id] = @user.id
        User.current = @user
      end

      def teardown_method!
        User.current = nil
        Setting.clear_cache
        Rails.cache.clear
        I18n.locale = :en
      end

      def with_wiki_approval_settings(updates)
        current = Setting.plugin_redmine_wiki_approval.symbolize_keys

        Setting.plugin_redmine_wiki_approval = current.merge(updates)
        Setting.clear_cache

        RedmineWikiApproval.instance_variable_set(:@settings, nil)
        RedmineWikiApproval.instance_variable_set(:@default_settings_redmine_wiki_approval, nil)

        yield
      ensure
        Setting.plugin_redmine_wiki_approval = current
        Setting.clear_cache
      end

      def with_project_wiki_settings(project, updates)
        setting = WikiApprovalSetting.find_or_initialize_by(project_id: project.id)

        # aktuellen Zustand sichern
        original = setting.attributes.slice(
          'wiki_comment_required',
          'wiki_draft_enabled',
          'wiki_approval_enabled',
          'wiki_approval_required',
          'wiki_approval_version',
          'wiki_content_draft',
          'wiki_sidebar_status',
          'wiki_templates'
        )

        # Updates anwenden
        updates.each do |key, value|
          setting.public_send("#{key}=", value)
        end

        setting.save!

        yield
      ensure
        # Restore
        original.each do |key, value|
          setting.public_send("#{key}=", value)
        end
        setting.save!
      end

      def ajax_html(body)
        html = body[/\.html\((["'])(.*)\1\);/m, 2]

        return nil unless html

        html
          .gsub('\"', '"')   # JS Quotes
          .gsub('\/', '/')   # escaped slashes
      end

      def create_wiki_tree(project)
        wiki = project.wiki
        template = create_page(wiki, "templates")

        # Root pages (Redmine hat kein echtes Root, das simulieren wir)
        global    = create_page(wiki, "Global", parent: template)
        project_n = create_page(wiki, "Project", parent: template)
        roles_n   = create_page(wiki, "Roles", parent: template)

        # --- GLOBAL ---
        create_page(wiki, "GlobTemplate 1", parent: global)
        create_page(wiki, "GlobTemplate 2", parent: global)

        # --- PROJECT ---
        subproject = create_page(wiki, project.identifier, parent: project_n)

        create_page(wiki, "Project 1", parent: subproject)
        create_page(wiki, "Projekt 2", parent: subproject)

        role_node = create_page(wiki, "Role-1", parent: subproject)
        manager   = create_page(wiki, "Manager proj", parent: role_node)

        create_page(wiki, "ManagerProject 1", parent: manager)
        create_page(wiki, "ManagerProject 2", parent: manager)

        # --- ROLES ---
        manager2 = create_page(wiki, "Manager", parent: roles_n)

        create_page(wiki, "Manager first", parent: manager2)
        create_page(wiki, "Manager second", parent: manager2)

        wiki
      end

      def create_page(wiki, title, parent: nil)
        page = WikiPage.new(wiki: wiki, title: title)
        page.parent = parent if parent
        page.content = WikiContent.new(page: page, text: "Test content template #{title}")
        page.save!

        WikiApprovalWorkflow.create!(
          page_id: page.id,
          version: page.content.version,
          status: :released,
          author_id: @admin.id
        )

        page
      end
    end

    class UnitCase < ActiveSupport::TestCase
      self.use_transactional_tests = true
      fixtures :all

      include WikiApproval::Test::PluginTestSetting

      def setup
        load_plugin_fixtures_in_order!
        load_default_values!
      end

      def teardown
        super
        teardown_method!
      end
    end

    class ControllerCase < Redmine::ControllerTest
      self.use_transactional_tests = true
      fixtures :all

      include WikiApproval::Test::PluginTestSetting

      def setup
        load_plugin_fixtures_in_order!
        load_default_values!
      end

      def teardown
        super
        teardown_method!
      end
    end

    class IntegrationCase < Redmine::IntegrationTest
      self.use_transactional_tests = true
      fixtures :all

      include WikiApproval::Test::PluginTestSetting

      def setup
        load_plugin_fixtures_in_order!
        load_default_values!
      end

      def teardown
        super
        teardown_method!
      end
    end

    class RoutingCase < Redmine::RoutingTest
      self.use_transactional_tests = true
      fixtures :all

      include WikiApproval::Test::PluginTestSetting

      def setup
        load_plugin_fixtures_in_order!
        load_default_values!
      end

      def teardown
        super
        teardown_method!
      end
    end
  end
end
