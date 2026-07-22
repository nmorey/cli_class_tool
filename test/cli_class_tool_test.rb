# frozen_string_literal: true

require 'test_helper'

# Define a mock parent module to test the CLI runner and utilities end-to-end
module MockApp
  class MockAppError < RuntimeError
  end
  class Common < CLIClassTool::Common
    # Override parent_module to point to MockApp
    def parent_module
      MockApp
    end

    # Expose private/protected helper for logging tests
    public :log
  end

  class TestAction < Common
    ACTION_LIST = [ :hello, :goodbye ]
    ACTION_HELP = {
      :hello => "Greet the user",
      :goodbye => "Say farewell"
    }

    class << self
      attr_accessor :opts_configured, :opts_checked

      def set_opts(action, parser, opts)
        self.opts_configured = true
        parser.on("--name NAME", "Name to greet") { |v| opts[:name] = v }
      end

      def check_opts(opts)
        self.opts_checked = true
        raise "Missing name" if opts[:action] == :hello && !opts[:name]
      end
    end

    def hello(opts)
      log(:INFO, "Hello, #{opts[:name]}!")
      return 0
    end

    def goodbye(opts)
      log(:WARNING, "Goodbye!")
      return 0
    end
  end

  ACTION_CLASS = [ TestAction ]
  extend CLIClassTool::Utils
end

module NestedApp
  class NestedAppError < StandardError; end

  class Common < CLIClassTool::Common
    def parent_module
      NestedApp
    end
    public :log
  end

  # Subcommand at Level 1 (automatic name "sub_one")
  module SubOne
    class SubOneError < StandardError; end
    class Common < CLIClassTool::Common
      def parent_module; SubOne; end
      public :log
    end

    class SubOneAction < Common
      ACTION_LIST = [ :run_one ]
      ACTION_HELP = { :run_one => "Run action of SubOne" }

      class << self
        def set_opts(action, parser, opts)
          parser.on("--foo FOO", "Foo option") { |v| opts[:foo] = v }
        end
        def check_opts(opts); end
      end

      def run_one(opts)
        log(:INFO, "SubOne executed with foo=#{opts[:foo]}")
        return 0
      end
    end

    ACTION_CLASS = [ SubOneAction ]
    extend CLIClassTool::Utils
  end

  # Subcommand with Custom name at Level 1 (using CLI_COMMAND_NAME)
  module SubTwoCustom
    CLI_COMMAND_NAME = "custom_sub"
    CLI_DESCRIPTION = "Custom Subcommand Help"

    class SubTwoCustomError < StandardError; end
    class Common < CLIClassTool::Common
      def parent_module; SubTwoCustom; end
    end

    # Level 2 deep nested subcommand within SubTwoCustom
    module DeepLevelTwo
      CLI_DESCRIPTION = "Deep Level Two CLI description"

      class DeepLevelTwoError < StandardError; end
      class Common < CLIClassTool::Common
        def parent_module; DeepLevelTwo; end
        public :log
      end

      class DeepAction < Common
        ACTION_LIST = [ :run_deep ]
        ACTION_HELP = { :run_deep => "Execute deepest level action" }

        class << self
          def set_opts(action, parser, opts)
            parser.on("--deep-val VALUE", "Deep option value") { |v| opts[:deep_val] = v }
          end
          def check_opts(opts); end
        end

        def run_deep(opts)
          log(:INFO, "DeepAction executed with deep_val=#{opts[:deep_val]}")
          return 42
        end
      end

      ACTION_CLASS = [ DeepAction ]
      extend CLIClassTool::Utils
    end

    extend CLIClassTool::Utils
  end

  CLI_COMMAND_ALIASES = {
    "myalias" => ["custom_sub", "deep_level_two", "run_deep"],
    "string_alias" => "sub_one run_one"
  }

  extend CLIClassTool::Utils
end

class CLIClassToolTest < Minitest::Test
  def setup
    MockApp.verbose_log = false
    MockApp::TestAction.opts_configured = false
    MockApp::TestAction.opts_checked = false
    String.class_variable_set(:@@is_a_tty, false)
  end

  # Test String colorization extensions
  def test_string_colorization_tty
    # Force TTY mode
    String.class_variable_set(:@@is_a_tty, true)

    assert_equal "\e[31mtest\e[0m", "test".red
    assert_equal "\e[32mtest\e[0m", "test".green
    assert_equal "\e[33mtest\e[0m", "test".brown
    assert_equal "\e[34mtest\e[0m", "test".blue
    assert_equal "\e[35mtest\e[0m", "test".magenta
  end

  def test_string_colorization_non_tty
    # Force non-TTY mode
    String.class_variable_set(:@@is_a_tty, false)

    assert_equal "test", "test".red
    assert_equal "test", "test".green
    assert_equal "test", "test".brown
    assert_equal "test", "test".blue
    assert_equal "test", "test".magenta
  end

  # Test CLIClassTool::Utils utilities
  def test_string_to_action
    assert_equal :hello, MockApp.stringToAction("hello")
    assert_equal :goodbye, MockApp.stringToAction("goodbye")

    assert_raises(RuntimeError) do
      MockApp.stringToAction("nonexistent")
    end
  end

  def test_action_to_string
    assert_equal "hello", MockApp.actionToString(:hello)
  end

  def test_get_action_attr
    list = MockApp.getActionAttr("ACTION_LIST")
    assert_equal [:hello, :goodbye, :list_actions], list

    help = MockApp.getActionAttr("ACTION_HELP")
    assert_equal "Greet the user", help[:hello]
    assert_equal "Say farewell", help[:goodbye]
  end

  # Test CLIClassTool::Common Logging output
  def test_logging_levels
    String.class_variable_set(:@@is_a_tty, false)
    action_instance = MockApp::TestAction.new

    # Info log
    out, err = capture_io do
      action_instance.log(:INFO, "Information message")
    end
    assert_equal "# INFO: Information message\n", out
    assert_empty err

    # Warning log
    out, err = capture_io do
      action_instance.log(:WARNING, "Warning message")
    end
    assert_equal "# WARNING: Warning message\n", out
    assert_empty err

    # Error log
    out, err = capture_io do
      action_instance.log(:ERROR, "Error message")
    end
    assert_empty out
    assert_equal "# ERROR: Error message\n", err

    # Progress log (carriage return)
    out, err = capture_io do
      action_instance.log(:PROGRESS, "Progress message")
    end
    assert_equal "# INFO: Progress message\r", out
    assert_empty err
  end

  def test_verbose_logging
    String.class_variable_set(:@@is_a_tty, false)
    action_instance = MockApp::TestAction.new

    # Verbose logging disabled
    MockApp.verbose_log = false
    out, _ = capture_io do
      action_instance.log(:VERBOSE, "Verbose message")
    end
    assert_empty out

    # Verbose logging enabled
    MockApp.verbose_log = true
    out, _ = capture_io do
      action_instance.log(:VERBOSE, "Verbose message")
    end
    assert_equal "# INFO: Verbose message\n", out
  end

  # Test minimal CLI client runner flow
  def test_run_cli_help
    exit_status = nil
    out, _ = capture_io do
      begin
        MockApp.run_cli({}, ["-h"])
      rescue SystemExit => e
        exit_status = e.status
      end
    end

    assert_equal 0, exit_status
    assert_match(/Usage:/, out)
    assert_match(/Possible actions:/, out)
    assert_match(/\* hello\s+Greet the user/, out)
  end

  def test_run_cli_action_success
    exit_status = nil
    out, _ = capture_io do
      begin
        MockApp.run_cli({}, ["hello", "--name", "Antigravity"])
      rescue SystemExit => e
        exit_status = e.status
      end
    end

    assert_equal 0, exit_status
    assert_match(/# INFO: Hello, Antigravity!/, out)
    assert MockApp::TestAction.opts_configured
    assert MockApp::TestAction.opts_checked
  end

  def test_run_cli_action_missing_params
    assert_raises(RuntimeError) do
      MockApp.run_cli({}, ["hello"])
    end
  end

  def test_load_addons_conflict
    require 'tmpdir'
    Dir.mktmpdir do |dir|
      # Create a custom unique addon file
      addon_file1 = File.join(dir, "custom_addon_abc.rb")
      File.write(addon_file1, "module MockApp; ADDON_ABC_LOADED = true; end")

      # Create an addon file with a name that is already required, like test_helper.rb
      addon_file2 = File.join(dir, "test_helper.rb")
      File.write(addon_file2, "module MockApp; CONFLICT_ADDON_LOADED = true; end")

      # Execute loadAddons
      MockApp.loadAddons(dir)

      # Verify that both files were loaded successfully and set their respective constants
      assert defined?(MockApp::ADDON_ABC_LOADED), "Unique addon file should have been loaded"
      assert defined?(MockApp::CONFLICT_ADDON_LOADED), "Conflicting name addon file should have been loaded"
    end
  end

  def test_run_error_custom_global_error_class_matching
    # Define the global [ModuleName]Error class first
    eval <<-RUBY
      module PatternMockApp
        class PatternMockAppError < StandardError; end
        extend CLIClassTool::Utils
      end
    RUBY
    assert defined?(PatternMockApp::RunError)
    assert_equal PatternMockApp::PatternMockAppError, PatternMockApp::RunError.superclass
  end

  def test_namespace_enforcement
    # Verify that trying to define a named subclass of CLIClassTool::Common in the global namespace raises an error
    assert_raises(RuntimeError) do
      eval("class GlobalActionClass < CLIClassTool::Common; end", TOPLEVEL_BINDING)
    end
  end

  def test_run_error_exception_behavior
    # Verify custom subclass attributes and message construction
    err = MockApp::RunError.new(42, "Standard failure output")
    assert_equal 42, err.err_code
    assert_equal "Standard failure output", err.msg
    assert_match(/Command failed with exit status 42/, err.message)
  end

  def test_nested_subcommand_discovery
    # Check that NestedApp dynamically discovered the two nested modules as sub-actions
    sub_actions = NestedApp.cli_sub_actions
    assert_equal 2, sub_actions.keys.size
    assert_equal NestedApp::SubOne, sub_actions["sub_one"]
    assert_equal NestedApp::SubTwoCustom, sub_actions["custom_sub"]

    # Check level 2 deep discovery
    sub_actions_l2 = NestedApp::SubTwoCustom.cli_sub_actions
    assert_equal 1, sub_actions_l2.keys.size
    assert_equal NestedApp::SubTwoCustom::DeepLevelTwo, sub_actions_l2["deep_level_two"]
  end

  def test_nested_subcommand_help_aggregation
    action_list = NestedApp.getActionAttr("ACTION_LIST")
    assert_includes action_list, :sub_one
    assert_includes action_list, :custom_sub

    action_help = NestedApp.getActionAttr("ACTION_HELP")
    assert_equal "", action_help[:sub_one] # SubOne has no CLI_DESCRIPTION/HELP constant
    assert_equal "Custom Subcommand Help", action_help[:custom_sub] # SubTwoCustom has CLI_DESCRIPTION
  end

  def test_nested_subcommand_execution_success
    exit_status = nil
    out, _ = capture_io do
      begin
        NestedApp.run_cli({}, ["sub_one", "run_one", "--foo", "hello_nested"])
      rescue SystemExit => e
        exit_status = e.status
      end
    end

    assert_equal 0, exit_status
    assert_match(/# INFO: SubOne executed with foo=hello_nested/, out)
  end

  def test_nested_subcommand_deep_execution_success
    exit_status = nil
    out, _ = capture_io do
      begin
        NestedApp.run_cli({}, ["custom_sub", "deep_level_two", "run_deep", "--deep-val", "ultra"])
      rescue SystemExit => e
        exit_status = e.status
      end
    end

    assert_equal 42, exit_status
    assert_match(/# INFO: DeepAction executed with deep_val=ultra/, out)
  end

  def test_nested_subcommand_help_flag
    exit_status = nil
    out, _ = capture_io do
      begin
        # Ask help from the level 2 subcommand deep_level_two
        NestedApp.run_cli({}, ["custom_sub", "deep_level_two", "-h"])
      rescue SystemExit => e
        exit_status = e.status
      end
    end

    assert_equal 0, exit_status
    assert_match(/Possible actions:/, out)
    assert_match(/\* run_deep\s+Execute deepest level action/, out)
  end

  def test_nested_subcommand_exception_matching_level_1
    # Create an exception from the level 1 subcommand
    err = NestedApp::SubOne::RunError.new(10, "SubOne failure")

    rescued = false
    begin
      raise err
    rescue NestedApp::NestedAppError => e
      rescued = true
      assert_equal 10, e.err_code
    end
    assert rescued, "Exception was not caught by parent NestedAppError"

    # Verify it can still be caught by its original name
    rescued_original = false
    begin
      raise err
    rescue NestedApp::SubOne::SubOneError
      rescued_original = true
    end
    assert rescued_original, "Exception was not caught by its original SubOneError"

    rescued_run_error = false
    begin
      raise err
    rescue NestedApp::SubOne::RunError
      rescued_run_error = true
    end
    assert rescued_run_error, "Exception was not caught by its exact RunError class"
  end

  def test_nested_subcommand_exception_matching_level_2
    # Create an exception from the level 2 deep subcommand
    err = NestedApp::SubTwoCustom::DeepLevelTwo::RunError.new(99, "DeepLevel failure")

    rescued_by_grandparent = false
    begin
      raise err
    rescue NestedApp::NestedAppError => e
      rescued_by_grandparent = true
      assert_equal 99, e.err_code
    end
    assert rescued_by_grandparent, "Exception was not caught by grandparent NestedAppError"

    rescued_by_parent = false
    begin
      raise err
    rescue NestedApp::SubTwoCustom::SubTwoCustomError
      rescued_by_parent = true
    end
    assert rescued_by_parent, "Exception was not caught by direct parent SubTwoCustomError"

    # Verify standard inheritance rejection still works correctly
    not_rescued = false
    begin
      raise err
    rescue NestedApp::SubOne::SubOneError
      not_rescued = true
    rescue NestedApp::NestedAppError
      # Should fall back here since SubOneError shouldn't match DeepLevelTwo's error
    end
    refute not_rescued, "Exception was incorrectly caught by a sibling error class"
  end

  def test_subcommand_with_no_actions_and_parent_with_actions
    eval <<-RUBY
      module LexicalTestApp
        class LexicalTestAppError < StandardError; end
        class Common < CLIClassTool::Common
          def parent_module; LexicalTestApp; end
        end
        class TopAction < Common
          ACTION_LIST = [:top_act]
          ACTION_HELP = { :top_act => "Top help" }
        end
        ACTION_CLASS = [ TopAction ]
        extend CLIClassTool::Utils

        module NestedNoActions
          class NestedNoActionsError < StandardError; end
          extend CLIClassTool::Utils
        end
      end
    RUBY

    list = nil
    begin
      list = LexicalTestApp::NestedNoActions.getActionAttr("ACTION_LIST")
    rescue => e
      flunk "Should not raise any error, but raised: #{e.class} - #{e.message}"
    end
    assert_equal [:list_actions], list
  end

  def test_action_class_without_action_help_or_list
    eval <<-RUBY
      module EmptyActionApp
        class EmptyActionAppError < StandardError; end
        class MiniAction
          # No ACTION_HELP or ACTION_LIST defined here
        end
        ACTION_CLASS = [ MiniAction ]
        extend CLIClassTool::Utils
      end
    RUBY

    assert_equal ({}), EmptyActionApp.getActionAttr("ACTION_HELP")
    # ACTION_LIST contains list_actions by default now
    assert_equal [:list_actions], EmptyActionApp.getActionAttr("ACTION_LIST")
  end

  def test_list_actions_on_nested_subcommand
    # Run list_actions on top-level app
    exit_status = nil
    out, _ = capture_io do
      begin
        NestedApp.run_cli({}, ["list_actions"])
      rescue SystemExit => e
        exit_status = e.status
      end
    end

    assert_equal 0, exit_status
    # Verify subcommands are listed, but list_actions is filtered out from printed output
    assert_match(/sub_one/, out)
    assert_match(/custom_sub/, out)
    refute_match(/list_actions/, out)

    # Run list_actions on Level 1 subcommand
    exit_status_sub = nil
    out_sub, _ = capture_io do
      begin
        NestedApp.run_cli({}, ["sub_one", "list_actions"])
      rescue SystemExit => e
        exit_status_sub = e.status
      end
    end

    assert_equal 0, exit_status_sub
    assert_match(/run_one/, out_sub)
    refute_match(/list_actions/, out_sub)
  end

  def test_sub_cli_listed_in_action_class_list_actions
    eval <<-RUBY
      module SubCliInActionClassApp
        class SubCliInActionClassAppError < StandardError; end
        module SubCLI
          class SubCLIError < StandardError; end
          extend CLIClassTool::Utils
        end
        # Include SubCLI module directly in ACTION_CLASS
        ACTION_CLASS = [ SubCLI ]
        extend CLIClassTool::Utils
      end
    RUBY

    exit_status = nil
    out, _ = capture_io do
      begin
        SubCliInActionClassApp.run_cli({}, ["list_actions"])
      rescue SystemExit => e
        exit_status = e.status
      end
    end

    assert_equal 0, exit_status
    assert_equal "sub_cli", out.strip
    refute_match(/list_actions/, out)
  end

  def test_command_alias_array_expansion
    exit_status = nil
    out, _ = capture_io do
      begin
        NestedApp.run_cli({}, ["myalias", "--deep-val", "expanded_val"])
      rescue SystemExit => e
        exit_status = e.status
      end
    end

    assert_equal 42, exit_status
    assert_match(/# INFO: DeepAction executed with deep_val=expanded_val/, out)
  end

  def test_command_alias_string_expansion
    exit_status = nil
    out, _ = capture_io do
      begin
        NestedApp.run_cli({}, ["string_alias", "--foo", "bar_val"])
      rescue SystemExit => e
        exit_status = e.status
      end
    end

    assert_equal 0, exit_status
    assert_match(/# INFO: SubOne executed with foo=bar_val/, out)
  end

  def test_command_alias_help_listing
    exit_status = nil
    out, _ = capture_io do
      begin
        NestedApp.run_cli({}, ["-h"])
      rescue SystemExit => e
        exit_status = e.status
      end
    end

    assert_equal 0, exit_status
    assert_match(/Command aliases:/, out)
    assert_match(/\* myalias\s+-> custom_sub deep_level_two run_deep/, out)
    assert_match(/\* string_alias\s+-> sub_one run_one/, out)
  end

  def test_nested_subcommand_aliases_and_shortcuts
    eval <<-RUBY
      module NestedAliasApp
        class NestedAliasAppError < StandardError; end

        class Common < CLIClassTool::Common
          def parent_module; NestedAliasApp; end
          public :log
        end

        module SubClass
          class SubClassError < StandardError; end
          class Common < CLIClassTool::Common
            def parent_module; SubClass; end
            public :log
          end

          module SubSubClass
            class SubSubClassError < StandardError; end
            class Common < CLIClassTool::Common
              def parent_module; SubSubClass; end
              public :log
            end

            class DeepAction < Common
              ACTION_LIST = [ :my_action ]
              ACTION_HELP = { :my_action => "Run deep action" }
              def my_action(opts)
                log(:INFO, "my_action executed!")
                return 77
              end
            end

            ACTION_CLASS = [ DeepAction ]
            extend CLIClassTool::Utils
          end

          CLI_COMMAND_ALIASES = {
            :shortcut => "sub_sub_class my_action"
          }

          extend CLIClassTool::Utils
        end

        CLI_COMMAND_ALIASES = {
          :shortcut2 => "sub_class shortcut"
        }

        extend CLIClassTool::Utils
      end
    RUBY

    # 1. Verify direct execution works: 'toplvl subclass subsubclass action'
    exit_status = nil
    out, _ = capture_io do
      begin
        NestedAliasApp.run_cli({}, ["sub_class", "sub_sub_class", "my_action"])
      rescue SystemExit => e
        exit_status = e.status
      end
    end
    assert_equal 77, exit_status
    assert_match(/# INFO: my_action executed!/, out)

    # 2. Verify alias on subclass works: 'toplvl subclass shortcut'
    exit_status = nil
    out, _ = capture_io do
      begin
        NestedAliasApp.run_cli({}, ["sub_class", "shortcut"])
      rescue SystemExit => e
        exit_status = e.status
      end
    end
    assert_equal 77, exit_status
    assert_match(/# INFO: my_action executed!/, out)

    # 3. Verify nested alias resolution works: 'toplvl shortcut2' -> 'toplvl subclass shortcut' -> 'toplvl subclass subsubclass action'
    exit_status = nil
    out, _ = capture_io do
      begin
        NestedAliasApp.run_cli({}, ["shortcut2"])
      rescue SystemExit => e
        exit_status = e.status
      end
    end
    assert_equal 77, exit_status
    assert_match(/# INFO: my_action executed!/, out)
  end
end
