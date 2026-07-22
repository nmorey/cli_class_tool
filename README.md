# CLIClassTool

`CLIClassTool` is a lightweight, object-oriented framework for building class-based command-line interface (CLI) applications. It decouples the generic execution, logging, and action routing engine from project-specific business logic, making it extremely easy to synchronize across multiple projects or package as a shared gem.

---

## Directory Structure

To use `CLIClassTool` in your project, copy or subtree the `cli_class_tool/` directory under your library path (typically `lib/`):

```
lib/
└── cli_class_tool/
    ├── README.md
    ├── common.rb       # Generic common helper class (logging, shell exec, prompt)
    ├── string.rb       # Generic String class extension for ANSI colors
    └── utils.rb        # Generic action routing and runner engine
```

---

## How to Use inside a Project

### 1. Define Your Custom Action Classes
Define classes representing categories of your CLI commands. These classes should inherit from your project's subclassed `Common` (which inherits from `CLIClassTool::Common`):

```ruby
module MyProject
  # Inherit from CLIClassTool::Common
  class Common < CLIClassTool::Common
    # Add any project-specific helpers here
  end
end

module MyProject
  class Suse < Common
    # 1. Declare the list of available actions (methods)
    ACTION_LIST = [ :source_rebase, :checkpatch ]

    # 2. Define action method help/descriptions
    ACTION_HELP = {
      :source_rebase => "Rebase SUSE kernel sources to the latest tip",
      :checkpatch    => "Run checkpatch on pending patches"
    }

    # 3. Implement action methods
    def source_rebase(opts)
      log(:INFO, "Rebasing...")
      run("git pull --rebase")
      return 0 # Return 0 for success (or an Integer exit code)
    end

    def checkpatch(opts)
      # Uses inherited `run` and logging methods
      ret = run("git diff HEAD~1")
      log(:VERBOSE, ret)
      return 0
    end
  end
end
```

### 2. Initialize and Load CLIClassTool
In your library entrypoint (e.g. `lib/my-project.rb`), require the `cli_class_tool` components, set up your project-specific namespace, and extend `CLIClassTool::Utils`:

```ruby
require 'cli_class_tool'

module MyProject
  # Define project-specific base Common class
  class Common < CLIClassTool::Common
    # Project-specific methods can be defined here
  end
end

# Require all your custom action classes
require 'my_project/suse'
require 'my_project/other_actions'

module MyProject
  # List of classes that implement various CLI actions
  ACTION_CLASS = [ Suse, OtherActions ]

  # Extend CLIClassTool::Utils to map methods onto MyProject module
  extend CLIClassTool::Utils
end
```

### 3. Create the Executable Runner
In your executable bin (e.g. `bin/mytool`), parse options and call the `execAction` utility to invoke the target action class:

```ruby
#!/usr/bin/ruby
require 'optparse'
require 'my-project'

opts = { action: :source_rebase } # Typically parsed from command-line arguments

# 1. Optionally parse options
optsParser = OptionParser.new
MyProject.setOpts(opts[:action], optsParser, opts)
optsParser.parse!(ARGV)

# 2. Check options validity
MyProject.checkOpts(opts)

# 3. Execute action dynamically
# Uses the class `load` factory method if defined, falling back to `.new`.
# If an exception is thrown, it will be caught and logged cleanly, returning the correct exit status.
exit MyProject.execAction(opts, opts[:action])
```

---

## Namespace Requirement & Error Handling

### 1. Module Namespace Requirement

To ensure clean encapsulation and safe error resolution, all action classes and standard subclasses inheriting from `CLIClassTool::Common` **must** be defined within a named module/class namespace (such as `MyProject`):

```ruby
# Correct: Action class is scoped under MyProject namespace
module MyProject
  class Suse < CLIClassTool::Common
    # ...
  end
end

# Incorrect: Defining action classes directly in the global namespace is forbidden
# and will raise an error at load-time:
class Suse < CLIClassTool::Common; end
# => "CLIClassTool action classes must be defined within a named module/class namespace"
```

### 2. Automated `RunError` Generation & Customized Inheritance

When your project's parent module extends `CLIClassTool::Utils`, `CLIClassTool` automatically generates a nested `RunError` class (i.e. `MyProject::RunError`) specifically for your project on load.

By default, this generated error inherits from `CLIClassTool::RunError`. However, if you have a binary-specific or project-wide base error class defined, `CLIClassTool` will **automatically detect it** and make `RunError` inherit from it instead!

It looks for existing error classes in this order:
1. `#{base_name}Error` (e.g., `MyProjectError` in the global scope)
2. `#{base_name}::Error` (e.g., `MyProject::Error` within your namespace)
3. Falls back to `CLIClassTool::RunError`

#### Why is this useful?
This allows you to catch all potential CLI errors (including system command failures from `run`, `runGit`, etc.) in a single rescue block at the entry point of your binary:

```ruby
# Define your binary-specific error class
class MyProjectError < StandardError; end

module MyProject
  extend CLIClassTool::Utils
  # CLIClassTool automatically defines MyProject::RunError inheriting from MyProjectError!
end

# In your executable (bin/mytool)
begin
  MyProject.run_cli
rescue MyProjectError => e
  # This cleanly catches MyProject::RunError, as well as any other custom MyProjectError!
  STDERR.puts "# ERROR: #{e.message}"
  exit e.respond_to?(:err_code) ? e.err_code : 1
end
```

---

## Logging Levels
By inheriting from `CLIClassTool::Common`, your action classes have access to a rich `log` helper supporting several standard output and color levels:

- `log(:DEBUG, "msg")`: Prints to STDOUT when `ENV["DEBUG"]` is active (Magenta).
- `log(:VERBOSE, "msg")`: Prints to STDOUT when `MyProject.verbose_log == true` (Blue).
- `log(:INFO, "msg")`: General informative logs (Green).
- `log(:PROGRESS, "msg")`: In-place update logs (Green with `\r` carriage return).
- `log(:WARNING, "msg")`: Warning logs (Brown).
- `log(:ERROR, "msg")`: Prints to STDERR (Red).

---

## Dynamic Class Overrides (Addons)

`CLIClassTool` natively supports dynamic class overrides (addons). This allows projects to load repository-specific or custom subclasses that extend or override base action behaviors without modifying the core codebase.

### 1. Set Up `getExtendedClass`

To enable class overrides, define a `getExtendedClass` class/module method on your parent module:

```ruby
module MyProject
  # Map of repository names to overridden classes
  @@custom_classes = {}

  def self.registerCustom(repo_name, classes)
    @@custom_classes[repo_name] = classes
  end

  # Resolve the customized/overridden subclass (addon) if registered
  def self.getExtendedClass(default_class, repo_name = File.basename(Dir.pwd))
    custom = @@custom_classes[repo_name]
    if custom != nil && custom[default_class] != nil
      return custom[default_class]
    else
      return default_class
    end
  end
end
```

If defined, `CLIClassTool` will automatically:
- Execute actions using the extended class instead of the base class.
- For options setup (`setOpts`) and validation checks (`checkOpts`), it will sequentially call BOTH the base class hooks and the extended class hooks to ensure clean options merging.

### 2. Dynamically Loading Addons

`CLIClassTool` provides a `loadAddons(path)` helper to dynamically scan a folder and load all custom Ruby classes/addons present in it.

```ruby
module MyProject
  extend CLIClassTool::Utils

  # Load all core addons
  loadAddons(File.expand_path('addons', __dir__))

  # Load optional user addons from an environment variable path
  if ENV["MY_PROJECT_ADDON_DIR"]
    loadAddons(ENV["MY_PROJECT_ADDON_DIR"])
  end
end
```

### 3. Factory Class Loading & Validation

`CLIClassTool` provides helper methods to implement safe, validated factory class loading. This ensures that subclasses are only instantiated through the authorized factory methods rather than being directly instantiated:

- `loadClass(default_class, addon_key, *args)`: Safely loads and instantiates an overridden/extended class instance.
- `checkDirectConstructor(class)`: Raises an error if the class is directly instantiated instead of going through `loadClass`.

#### Example Setup:

```ruby
module MyProject
  class Suse < Common
    def initialize(path)
      # Validate that constructor was only called through loadClass factory
      MyProject.checkDirectConstructor(self.class)
      @path = path
    end

    # Factory loading method
    def self.load(path=".")
      # Safely instantiate via CLIClassTool loadClass
      return MyProject.loadClass(Suse, "suse-addon-key", path)
    end
  end
end
```

### 4. Fully Automated CLI Runner (`run_cli`)

`CLIClassTool` provides a highly configurable, automated CLI runner (`run_cli`) that eliminates repetitive parsing and formatting boilerplate from your executable binaries.

- `run_cli(opts={}, argv=ARGV) { |parser, phase, action_opts| ... }`

#### Built-in Default Options:
To simplify applications, `run_cli` natively defines and handles standard options by default:
- `--verbose`: Handled both globally and action-specifically, setting `MyProject.verbose_log = true`.
- `-y`, `--yes` and `-n`, `--no`: Handled action-specifically, setting `opts[:yn_default] = :yes` or `:no` respectively (which is natively recognized by the inherited `confirm` method).

#### Customization Phases:
- `:global`: Customize options parsed globally before the action is matched.
- `:action`: Customize options parsed specifically for the targeted action.

#### Addon Help Integration (`getCustomClasses`):
If your project uses dynamic class overrides (addons) and defines a `getCustomClasses` method on the parent module returning a hash/list of registered addon names, `run_cli` will automatically append a list of these custom repository addons to the `--help` output of the CLI for seamless help integration.

#### Example Executable (`bin/mytool`):

```ruby
#!/usr/bin/ruby
require 'my-project'

opts = {
  :default_setting => "value"
}

# The entire CLI parsing, formatting, listing, option checking, and action routing is fully automated!
# Built-in options like --verbose, -y/--yes, -n/--no are parsed and processed automatically.
MyProject.run_cli(opts) do |parser, phase, action_opts|
  case phase
  when :global
    parser.on("-c", "--config FILE") { |val| MyProject::Config.path = val }
  end
end
```

---

## Nested CLI Subcommands (Subcommands & Recursive Routing)

`CLIClassTool` natively supports nested CLI subcommands, enabling hierarchical structures of the form:
```
$ mytool <subcommand> <action> [options]
$ mytool <subcommand> <sub_subcommand> <action> [options]
```

This allows you to decouple complex tools into self-contained sub-CLI components while executing them seamlessly under a single binary entry point.

### 1. Auto-Discovery & Setup

Any nested module or class defined within your parent CLI module that extends `CLIClassTool::Utils` is **automatically discovered** as a subcommand:

```ruby
module MyProject
  extend CLIClassTool::Utils # Parent CLI

  # 1. Nesting a subcommand module
  module ConfigCLI
    # Define custom subcommand help description
    CLI_DESCRIPTION = "Manage application configurations"

    # Optional: Customize the command name (defaults to "config_cli")
    CLI_COMMAND_NAME = "config"

    class ConfigError < StandardError; end

    class Common < CLIClassTool::Common
      def parent_module; ConfigCLI; end
    end

    class ConfigAction < Common
      ACTION_LIST = [ :set_val ]
      ACTION_HELP = { :set_val => "Set a config value" }

      def set_val(opts)
        # business logic...
        return 0
      end
    end

    ACTION_CLASS = [ ConfigAction ]
    extend CLIClassTool::Utils
  end
end
```

### 2. Help Aggregation & Name Resolution

- **Naming:** By default, subcommand trigger words are derived from the inner module/class name converted to `snake_case` (e.g., `ConfigCLI` becomes `config_cli`). Define `CLI_COMMAND_NAME = "custom_name"` on your submodule to override this behavior.
- **Help Menus:** Nested subcommands and their descriptions (`CLI_DESCRIPTION` or `HELP` constants) are automatically collected and listed in the parent CLI's usage output under `Possible actions:`.
- **Option Forwarding:** Global customization blocks and verbosity flags are recursively passed down to the active subcommand.

### 3. Command Aliases (Shortcuts)

You can define command shortcuts/aliases at any CLI level by declaring a `CLI_COMMAND_ALIASES` Hash constant mapping shortcut names (symbols or strings) to subcommand/action pathways:

```ruby
module MyProject
  extend CLIClassTool::Utils

  # Map shortcuts to deeply-nested actions
  CLI_COMMAND_ALIASES = {
    "myalias"       => ["config", "set_val"],
    "string_alias"  => "config set_val"
  }
end
```

Running `$ mytool myalias --foo bar` will automatically expand and route arguments exactly as if the user had typed `$ mytool config set_val --foo bar`.
These shortcuts are also dynamically collected and formatted under a dedicated `Command aliases:` section when printing `--help`.

### 4. Seamless Subcommand Exception Handling

`CLIClassTool` provides dynamic subclass exception matching to solve a common design challenge: *rescuing any exception originating from nested sub-CLIs under a single, central parent rescue block.*

When you extend `CLIClassTool::Utils` on a parent module, `CLIClassTool` overrides the case-equality (`===`) operator on the parent's base error class. This ensures:
- Any child subcommand exception (such as `MyProject::ConfigCLI::RunError`) is **seamlessly rescued** by the parent base error class.
- The original exception classes and names remain **completely unchanged**, meaning they can still be rescued by their specific sub-CLI exception class as normal.

This enables infinite sub-CLI nesting while preserving modular reuse across different parent projects or as standalone binaries:

```ruby
# In bin/mytool
begin
  MyProject.run_cli
rescue MyProjectError => e
  # Seamlessly catches errors from MyProject::RunError,
  # MyProject::ConfigCLI::RunError, or any deeper sublevel!
  STDERR.puts "# ERROR: #{e.message}"
  exit e.respond_to?(:err_code) ? e.err_code : 1
end
```

```
