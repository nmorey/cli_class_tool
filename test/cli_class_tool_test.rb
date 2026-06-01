# frozen_string_literal: true

require 'test_helper'

# Define a mock parent module to test the CLI runner and utilities end-to-end
module MockApp
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
    assert_equal [:hello, :goodbye], list

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

  def test_run_error_default_generation
    # By default, extending Utils should generate a RunError inheriting from CLIClassTool::RunError
    eval <<-RUBY
      module DefaultMockApp
        extend CLIClassTool::Utils
      end
    RUBY
    assert defined?(DefaultMockApp::RunError)
    assert_equal CLIClassTool::RunError, DefaultMockApp::RunError.superclass
  end

  def test_run_error_custom_global_error_class_matching
    # Define the global [ModuleName]Error class first
    eval <<-RUBY
      class PatternMockAppError < StandardError; end
      module PatternMockApp
        extend CLIClassTool::Utils
      end
    RUBY
    assert defined?(PatternMockApp::RunError)
    assert_equal PatternMockAppError, PatternMockApp::RunError.superclass
  end

  def test_run_error_custom_inner_error_class_matching
    # Define an inner module Error class first
    eval <<-RUBY
      module InnerMockApp
        class Error < StandardError; end
        extend CLIClassTool::Utils
      end
    RUBY
    assert defined?(InnerMockApp::RunError)
    assert_equal InnerMockApp::Error, InnerMockApp::RunError.superclass
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
    assert_equal "Standard failure output", err.output
    assert_match(/Command failed with exit status 42/, err.message)
    assert_match(/Standard failure output/, err.message)
  end
end
