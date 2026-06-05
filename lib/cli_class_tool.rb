module CLIClassTool
    def self.define_run_error(parent_module, superclass)
        klass = Class.new(superclass)

        klass.class_eval do
            attr_reader :err_code, :msg

            def initialize(err_code, output = nil)
                @err_code = err_code
                @msg = output
                super("Command failed with exit status #{err_code}")
            end
        end
        parent_module.const_set(:RunError, klass)
    end

end

require_relative 'cli_class_tool/string'
require_relative 'cli_class_tool/common'
require_relative 'cli_class_tool/utils'
