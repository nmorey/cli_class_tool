module CLIClassTool
  class RunError < StandardError
    attr_reader :err_code, :output

    def initialize(err_code, output = nil)
      @err_code = err_code
      @output = output
      super("Command failed with exit status #{err_code}#{output ? "\n#{output}" : ''}")
    end
  end

  def self.define_run_error(parent_module, superclass = CLIClassTool::RunError)
    klass = Class.new(superclass)

    if !(superclass <= CLIClassTool::RunError)
      klass.class_eval do
        attr_reader :err_code, :output

        def initialize(err_code, output = nil)
          @err_code = err_code
          @output = output
          super("Command failed with exit status #{err_code}#{output ? "\n#{output}" : ''}")
        end
      end
    end

    parent_module.const_set(:RunError, klass)
  end
end

require_relative 'cli_class_tool/string'
require_relative 'cli_class_tool/common'
require_relative 'cli_class_tool/utils'
