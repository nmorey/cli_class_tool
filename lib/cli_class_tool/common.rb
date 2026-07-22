# Main module for generic CLI class-based tools and utilities
module CLIClassTool

    # Logger for CLIClassTool::Common
    module Logger
        private
        # Internal log method
        # @param lvl [String] Log level string (colored)
        # @param str [String] Message
        # @param out [IO] Output stream (default $stdout)
        def _log(lvl, str, out=$stdout)
            out.puts("# " + lvl.to_s() + ": " + str)
        end

        # Internal relog method (update current line)
        # @param lvl [String] Log level string (colored)
        # @param str [String] Message
        # @param out [IO] Output stream (default $stdout)
        def _relog(lvl, str, out=$stdout)
            out.print("# " + lvl.to_s() + ": " + str + "\r")
        end

        # Compute the parent module of an object or a class
        #
        # @param obj [Object,Class] Object or class to get the Module from
        # @raise [StandardError] If command failed
        def obj_to_parent_mod(obj)
            return obj if obj.class == Module

            theClass = obj.is_a?(Class) ? obj : obj.class
            if theClass.name.nil?
                return Object
            else
                parts = theClass.name.split('::')
                if parts.size <= 1
                    raise "CLIClassTool action classes must be defined within a named module/class namespace"
                end
                return Object.const_get(parts[0...-1].join('::'))
            end
        end

        # Get the parent module of this class (e.g. KernelWork or XXX)
        def parent_module
            return @parent_module if @parent_module != nil

            @parent_module = obj_to_parent_mod(self)
            return @parent_module
        end

        public
        # Log a message with a specific level
        #
        # @param lvl [Symbol] Log level (:DEBUG, :INFO, :WARNING, :ERROR, etc.)
        # @param str [String] Message to log
        def log(lvl, str)
            case lvl
            when :DEBUG
                _log("DEBUG".magenta(), str) if ENV["DEBUG"].to_s() != ""
            when :DEBUG_CI
                _log("DEBUG_CI".magenta(), str) if ENV["DEBUG_CI"].to_s() != ""
            when :VERBOSE
                _log("INFO".blue(), str) if parent_module.verbose_log == true
            when :INFO
                _log("INFO".green(), str)
            when :PROGRESS
                _relog("INFO".green(), str)
            when :WARNING
                _log("WARNING".brown(), str)
            when :ERROR
                _log("ERROR".red(), str, $stderr)
            else
                _log(lvl, str)
            end
        end

        # Prompt the user for confirmation
        #
        # @param opts [Hash] Options hash
        # @param msg [String] Confirmation message
        # @param ignore_default [Boolean] Ignore default yes/no options
        # @param allowed_reps [Array<String>] Allowed responses
        # @return [String] User response
        def confirm(opts, msg, ignore_default=false, allowed_reps=[ "y", "n" ])
            rep = 't'
            while allowed_reps.index(rep) == nil && rep != '' do
                puts "Do you wish to #{msg} ? (#{allowed_reps.join("/")}): "
                case (ignore_default == true ? nil : opts[:yn_default])
                when :no
                    puts "Auto-replying no due to --no option"
                    rep = 'n'
                when :yes
                    puts "Auto-replying yes due to --yes option"
                    rep = 'y'
                else
                    rep = STDIN.gets.chomp()
                end
            end
            return rep
        end
    end

    # Common utility class providing logging, configuration, and shell execution methods
    class Common
        # Hook to enforce namespace loading at load time
        def self.inherited(subclass)
            if subclass.name
                parts = subclass.name.to_s.split('::')
                if parts.size <= 1
                    raise "CLIClassTool action classes must be defined within a named module/class namespace"
                end
            end
        end

        # List of available actions for this class
        ACTION_LIST = [ :list_actions ]
        # Help text for actions
        ACTION_HELP = {}

        # Give the Logger mathods to Common
        include CLIClassTool::Logger

        private
        # Raise error if system command failed
        # @param check_err [Boolean] Whether to check for errors
        # @param sysret [Process::Status] System return status
        # @param ret [String, nil] Optional return message
        # @raise [StandardError] If command failed
        def abort_if_err(check_err, sysret, ret = nil)
            if sysret.exitstatus != 0 && check_err == true
                unless parent_module.const_defined?(:RunError)
                    raise "CLIClassTool parent module #{parent_module} must extend CLIClassTool::Utils to define RunError"
                end
                raise(parent_module::RunError.new(sysret.exitstatus, ret))
            end
        end

        # Debug command execution
        # @param cmd_type [String] Type of command (e.g., 'git')
        # @param cmd [String] The command string
        def cmd_debug(cmd_type, cmd)
            log(:DEBUG, "Called from:")
            depth=1
            if ENV["DEBUG_CALL_DEPTH"].to_s() != ""
                depth = ENV["DEBUG_CALL_DEPTH"].to_i()
            end
            [ depth, caller.length].min.downto(1){|x|
                log(:DEBUG, " #{caller[x]}")
            }
            log(:DEBUG, "Running #{cmd_type} command '#{cmd}'")
        end


        public
        # Simple initializer for a Common object
        #
        # @param path [String] Path to run commands from
        def initialize(path=".", caller_obj=self)
            @path = path
            @parent_module = obj_to_parent_mod(caller_obj)
        end

        # Run a shell command
        #
        # @param cmd [String] Command to run
        # @param check_err [Boolean] Raise error on failure
        # @return [String] Command output
        # @raise [StandardError] If command fails and check_err is true
        def run(cmd, check_err = true)
            cmd_debug('', cmd)
            ret = `cd #{@path} && #{cmd}`.chomp()
            abort_if_err(check_err, $?, ret)
            return ret
        end

        def self.run(path, cmd, check_err = true)
            obj = Common.new(path, self)
            return obj.run(cmd, check_err)
        end
        # Run a shell command using system() (interactive)
        #
        # @param cmd [String] Command to run
        # @param check_err [Boolean] Raise error on failure
        # @return [Boolean] Command success status
        # @raise [StandardError] If command fails and check_err is true
        def runSystem(cmd, check_err = true)
            cmd_debug('interactive', cmd)
            ret = system("cd #{@path} && #{cmd}")
            abort_if_err(check_err, $?)
            return ret
        end

        # Run a git command
        #
        # @param cmd [String] Git command arguments
        # @param opts [Hash] Options (e.g., :env)
        # @param check_err [Boolean] Raise error on failure
        # @return [String] Command output
        # @raise [StandardError] If command fails and check_err is true
        def runGit(cmd, opts={}, check_err = true)
            cmd_debug('git', cmd)
            ret = `cd #{@path} && #{opts[:env]} git #{cmd}`.chomp()
            abort_if_err(check_err, $?, ret)
            return ret
        end

        # Run a git command interactively
        #
        # @param cmd [String] Git command arguments
        # @param opts [Hash] Options (e.g., :env)
        # @param check_err [Boolean] Raise error on failure
        # @return [Boolean] Command success status
        # @raise [StandardError] If command fails and check_err is true
        def runGitInteractive(cmd, opts={}, check_err = true)
            cmd_debug('git interactive', cmd)
            ret = system("cd #{@path} && #{opts[:env]} git #{cmd}")
            abort_if_err(check_err, $?)
            return ret
        end

        # List available actions
        #
        # @param opts [Hash] Options hash
        # @return [Integer] 0
        def list_actions(opts)
            actions = parent_module.getActionAttr("ACTION_LIST").map(){|x| parent_module.actionToString(x)}
            actions.reject! { |x| x == "list_actions" }
            puts actions.join("\n")
            return 0
        end
    end
end
