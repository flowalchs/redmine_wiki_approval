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
          role.add_permission! :wiki_draft_create
        end
        @project = Project.find 1
        @project2 = Project.find 2
        @project3 = Project.find 3
        [@project, @project3].each do |project|
          project.enable_module! :wiki_approval
        end
        Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_comment] = 'false'
        Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_draft_enabled] = 'true'
        Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_enabled] = 'project'
        Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_required] = 'project'
        Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_version] = 'true'
        Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_draft_enabled] = 'true'
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
