module CLIClassTool
    # Generic utilities for CLI class-based actions
    module Utils

        # Hook called when a module extends CLIClassTool::Utils
        def self.extended(base)
            return if base == nil

            lower_mod = base.name.split('::')[-1]
            superclass_name = "#{base.name}::#{lower_mod}Error"

            if ! Object.const_defined?(superclass_name)
                raise("Could not find a base error class named #{superclass_name}")
            end

            error_class = Object.const_get(superclass_name)

            # Override === on the error class to match nested subcommand errors recursively
            error_class.singleton_class.class_eval do
                define_method(:_cli_host_module) { base }

                def ===(other)
                    return true if super

                    if other.is_a?(StandardError) && other.respond_to?(:err_code)
                        other_class_name = other.class.name
                        if other_class_name
                            parts = other_class_name.split('::')
                            if parts.size > 1
                                parent_mod_name = parts[0...-1].join('::')
                                host = _cli_host_module
                                if host.respond_to?(:cli_sub_actions)
                                    all_sub_names = _all_sub_module_names(host)
                                    return all_sub_names.include?(parent_mod_name)
                                end
                            end
                        end
                    end

                    false
                end

                define_method(:_all_sub_module_names) do |host_mod|
                    names = []
                    if host_mod.respond_to?(:cli_sub_actions)
                        host_mod.cli_sub_actions.values.each do |sub_cli|
                            if sub_cli.name
                                names << sub_cli.name
                                names.concat(_all_sub_module_names(sub_cli))
                            end
                        end
                    end
                    names.uniq
                end
            end

            CLIClassTool.define_run_error(base, error_class)
        end

        # Convert CamelCase to snake_case
        # @param str [String]
        # @return [String]
        def _to_snake_case(str)
            str.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
               .gsub(/([a-z\d])([A-Z])/, '\1_\2')
               .tr('-', '_')
               .downcase
        end

        # Dynamically discover and return a map of sub-CLI tools
        #
        # @return [Hash<String, Module>] Map of subcommand string to CLI modules
        def cli_sub_actions
            sub_actions = {}

            # First, check if manual CLI_SUB_ACTIONS mapping exists
            if self.const_defined?(:CLI_SUB_ACTIONS)
                manual_actions = self::CLI_SUB_ACTIONS
                if manual_actions.is_a?(Hash)
                    manual_actions.each do |k, v|
                        sub_actions[k.to_s] = v
                    end
                end
            end

            # Then, dynamically discover any inner modules/classes extending CLIClassTool::Utils
            self.constants(false).each do |const_sym|
                begin
                    const_val = self.const_get(const_sym)
                    if const_val.is_a?(Module) && const_val.is_a?(CLIClassTool::Utils)
                        cmd_name = if const_val.const_defined?(:CLI_COMMAND_NAME)
                            const_val::CLI_COMMAND_NAME.to_s
                        else
                            _to_snake_case(const_sym.to_s)
                        end
                        # Only add if not already manually specified
                        sub_actions[cmd_name] ||= const_val
                    end
                rescue NameError, LoadError
                    # ignore uninitialized autoloads
                end
            end

            return sub_actions
        end

        # Convert a string to an action symbol, validating it against available actions
        #
        # @param str [String] Action name
        # @return [Symbol] Action symbol
        # @raise [RuntimeError] If action is invalid
        def stringToAction(str)
            action = str.to_sym()
            raise("Invalid action '#{str}'") if self.getActionAttr("ACTION_LIST").index(action) == nil
            return action
        end

        # Convert an action symbol to a string
        #
        # @param sym [Symbol] Action symbol
        # @return [String] Action name
        def actionToString(sym)
            return sym.to_s()
        end

        # Get attributes from all action classes
        #
        # @param attr [Symbol] Attribute name (e.g., "ACTION_LIST")
        # @return [Hash, Array] Aggregated attributes
        def getActionAttr(attr)
            common_class = self.const_defined?(:Common) ? self::Common : CLIClassTool::Common
            is_hash = if common_class.const_defined?(attr)
                common_class.const_get(attr).is_a?(Hash)
            else
                attr.to_s.include?("HELP")
            end

            action_classes = self.const_defined?(:ACTION_CLASS) ? self::ACTION_CLASS : []

            # Resolve overridden/extended class (addon) if getExtendedClass is defined
            resolved_classes = action_classes.map do |x|
                self.respond_to?(:getExtendedClass) ? self.getExtendedClass(x) : x
            end

            res = if is_hash
                resolved_classes.inject({}) do |h, x|
                    x.const_defined?(attr) ? h.merge(x.const_get(attr)) : h
                end
            else
                resolved_classes.map do |x|
                    x.const_defined?(attr) ? x.const_get(attr) : []
                end.flatten()
            end

            # If it's ACTION_LIST, append discovered subcommand names
            if attr.to_s == "ACTION_LIST"
                sub_actions = self.cli_sub_actions
                res += sub_actions.keys.map(&:to_sym)
                res << :list_actions unless res.include?(:list_actions)
            # If it's ACTION_HELP, merge subcommand helps
            elsif attr.to_s == "ACTION_HELP"
                sub_helps = {}
                self.cli_sub_actions.each do |cmd_name, sub_cli|
                    desc = ""
                    if sub_cli.const_defined?(:CLI_DESCRIPTION)
                        desc = sub_cli::CLI_DESCRIPTION
                    elsif sub_cli.const_defined?(:HELP)
                        desc = sub_cli::HELP
                    end
                    sub_helps[cmd_name.to_sym] = desc
                end
                if self.const_defined?(:CLI_SUB_ACTIONS_HELP)
                    self::CLI_SUB_ACTIONS_HELP.each do |k, desc|
                        sub_helps[k.to_sym] = desc
                    end
                end
                res = res.merge(sub_helps)
            end

            return res
        end

        # Run a block on the class responsible for a specific action
        #
        # @param action [Symbol] The action
        # @param sym [Symbol, nil] Optional method to check for existence
        # @yield [Class] The class handling the action
        # @return [Object] Result of the block or error code
        def _runOnClass(action, sym, &block)
            return -1 unless self.const_defined?(:ACTION_CLASS)
            self::ACTION_CLASS.each(){|x|
                next if !x.const_defined?(:ACTION_LIST) || x::ACTION_LIST.index(action) == nil

                # Resolve overridden/extended class (addon)
                class_to_use = self.respond_to?(:getExtendedClass) ? self.getExtendedClass(x) : x

                if sym != nil
                    has_base = x.singleton_methods().index(sym) != nil
                    has_addon = class_to_use != x && class_to_use.singleton_methods().index(sym) != nil

                    if has_base || has_addon
                        yield(x) if has_base
                        yield(class_to_use) if has_addon
                        return 0
                    end
                else
                    return yield(class_to_use)
                end
                return 0
            }
            return -1
        end

        # Set options for an action
        #
        # @param action [Symbol] The action
        # @param optsParser [OptionParser] The option parser
        # @param opts [Hash] The options hash
        def setOpts(action, optsParser, opts)
            self._runOnClass(action, :set_opts) {|kClass|
                kClass.set_opts(action, optsParser, opts)
            }
        end

        # Check options for validity
        #
        # @param opts [Hash] The options hash
        def checkOpts(opts)
             self._runOnClass(opts[:action], :check_opts) {|kClass|
                 kClass.check_opts(opts)
            }
        end

        # Execute an action
        #
        # @param opts [Hash] The options hash
        # @param action [Symbol] The action to execute
        # @param error_class [Class, nil] Optional base error class to rescue
        # @return [Object] Result of the action (often an Integer exit code)
        def execAction(opts, action, error_class = nil)
            caught_error_class = error_class || StandardError

            ret_code = self._runOnClass(action, nil) {|kClass|
                begin
                    # Use load factory method if defined, else fall back to .new
                    obj = kClass.respond_to?(:load) ? kClass.load() : kClass.new()
                    ret = obj.public_send(action, opts)

                    return ret.is_a?(Integer) ? ret : 0
                rescue caught_error_class => e
                    puts("# " + "ERROR".red().to_s() + ": Action '#{action}' failed: #{e.message}")
                    e.backtrace.each(){|l|
                        puts("# " + "ERROR".red().to_s() + ": \t" + l)
                    } if self.verbose_log

                    begin
                        return e.err_code
                    rescue
                        return 1
                    end
                end
            }

            if ret_code == -1 && action == :list_actions
                actions = self.getActionAttr("ACTION_LIST").map(){|x| self.actionToString(x)}
                actions.reject! { |x| x == "list_actions" }
                puts actions.join("\n")
                return 0
            end

            return ret_code
        end

        # Set verbose logging
        #
        # @param val [Boolean] True to enable verbose logging
        def verbose_log=(val)
            @verbose_log = val
        end

        # Get verbose logging status
        #
        # @return [Boolean] Verbose logging status
        def verbose_log()
            @verbose_log
        end

        # Load all custom addon classes/files from a directory
        #
        # @param path [String] Absolute or relative directory path containing .rb files
        def loadAddons(path)
            return unless Dir.exist?(path)

            absolute_dir = File.expand_path(path)
            Dir.entries(absolute_dir).each() do |entry|
                absolute_file = File.join(absolute_dir, entry)
                next if !File.file?(absolute_file) || entry !~ /\.rb$/
                require absolute_file
            end
        end

        # Safely load an overridden/extended class instance using a generic addon_key
        def loadClass(default_class, addon_key, *more)
            @load_class ||= []
            @load_class.push(default_class)

            # Resolve overridden class using getExtendedClass if available
            extended_class = self.respond_to?(:getExtendedClass) ? self.getExtendedClass(default_class, addon_key) : default_class
            obj = extended_class.new(*more)
            @load_class.pop()
            return obj
        end

        # Validate that the constructor was only called through loadClass
        def checkDirectConstructor(theClass)
            @load_class ||= []
            curLoad = @load_class.last()
            cl = theClass
            while cl != Object
                return if cl == curLoad
                cl = cl.superclass
            end
            raise("Use #{self.name}::loadClass to construct a #{theClass} class")
        end

        # Generic CLI runner and argument parser for class-based applications.
        #
        # @param opts [Hash] Initial options hash
        # @param argv [Array<String>] Command line arguments (defaults to ARGV)
        # @yield [parser, phase, action_opts] Custom options setup callback block
        def run_cli(opts = {}, argv = ARGV, &block)
            # Fetch actions and action helps
            action_helps = self.getActionAttr("ACTION_HELP")

            # 1. Action Parser Setup
            action_parser = OptionParser.new(nil, 60)
            action_parser.banner = "Usage: #{$0} <action> [action options]"
            action_parser.separator ""
            action_parser.separator "Options:"
            action_parser.on("-h", "--help", "Display usage.") { puts action_parser.to_s; exit 0 }
            action_parser.on("--verbose", "Displays more informations.") { self.verbose_log = true }

            # Yield parser to allow caller to customize the global options
            yield(action_parser, :global, opts) if block_given?

            action_parser.separator "Possible actions:"

            # Format actions nicely with padding
            max_len = action_helps.keys.map { |k| self.actionToString(k).length }.max || 0
            col_width = max_len + 4
            action_helps.each do |k, x|
                indent = col_width - self.actionToString(k).length
                action_parser.separator "\t * " + self.actionToString(k) + (" " * indent) + x.to_s
            end

            # Include any registered custom addon class listings if defined
            if self.respond_to?(:getCustomClasses) && self.getCustomClasses.length > 0
                action_parser.separator "Custom repo addons available:"
                self.getCustomClasses.each do |k, x|
                    action_parser.separator "\t * #{k}"
                end
            end

            rest = action_parser.order!(argv)
            if rest.length <= 0
                STDERR.puts("Error: No action provided")
                puts action_parser.to_s
                exit 1
            end

            action_s = argv[0]

            # Intercept subcommands here!
            sub_actions = self.cli_sub_actions
            if sub_actions.key?(action_s)
                sub_cli = sub_actions[action_s]
                if sub_cli.respond_to?(:verbose_log=)
                    sub_cli.verbose_log = self.verbose_log
                end
                argv.shift()
                if block
                    exit(sub_cli.run_cli(opts, argv, &block))
                else
                    exit(sub_cli.run_cli(opts, argv))
                end
            end

            action = opts[:action] = self.stringToAction(action_s)
            argv.shift()

            # 2. Options Parser Setup
            opts_parser = OptionParser.new(nil, 60)
            opts_parser.banner = "Usage: #{$0} #{action_s} "
            opts_parser.separator "# " + action_helps[action].to_s()
            opts_parser.separator ""
            opts_parser.separator "Options:"
            opts_parser.on("-h", "--help", "Display usage.") { puts opts_parser.to_s; exit 0 }
            opts_parser.on("-n", "--no", "Assume no to all questions.") { opts[:yn_default] = :no }
            opts_parser.on("-y", "--yes", "Assume yes to all questions.") { opts[:yn_default] = :yes }
            opts_parser.on("--verbose", "Displays more informations.") { self.verbose_log = true }

            # Provide custom block hook for option parser customization
            yield(opts_parser, :action, opts) if block_given?

            # Set options on classes
            self.setOpts(action, opts_parser, opts)

            # Order remaining arguments
            if opts[:ignore_opts] != true
                rest = opts_parser.order!(argv)
                raise("Extra Unexpected extra arguments provided: " + rest.map(){|x|"'" + x + "'"}.join(", ")) if rest.length != 0
            else
                opts[:extra_args] = argv
            end

            # Validate options and execute action
            self.checkOpts(opts)
            exit self.execAction(opts, action)
        end
    end
end
