# Extension to the core String class to add colorization support
class String
    # colorization
    @@is_a_tty = nil

    # Colorize the string using ANSI escape codes
    #
    # @param color_code [Integer] ANSI color code
    # @return [String] Colorized string if TTY, else original string
    def colorize(color_code)
        @@is_a_tty = $stdout.isatty() if @@is_a_tty == nil
        if @@is_a_tty then
            if self =~ /\A\e\[([\d;]+)m(.*)\e\[0m\z/
                codes = $1.split(';')
                content = $2
                new_codes = codes.dup
                if color_code.to_i == 1
                    new_codes.unshift("1") unless new_codes.include?("1")
                else
                    new_codes.reject! { |c| (30..37).include?(c.to_i) || (90..97).include?(c.to_i) }
                    new_codes << color_code.to_s
                end
                new_codes.uniq!
                new_codes.sort_by! { |c| c.to_i }
                return "\e[#{new_codes.join(';')}m#{content}\e[0m"
            else
                return "\e[#{color_code}m#{self}\e[0m"
            end
        else
            return self
        end
    end

    # Make the string black
    # @return [String] Black string
    def black
        colorize(30)
    end

    # Make the string red
    # @return [String] Red string
    def red
        colorize(31)
    end

    # Make the string green
    # @return [String] Green string
    def green
        colorize(32)
    end

    # Make the string brown (yellow)
    # @return [String] Brown string
    def brown
        colorize(33)
    end

    # Make the string yellow
    # @return [String] Yellow string
    def yellow
        colorize(33)
    end

    # Make the string blue
    # @return [String] Blue string
    def blue
        colorize(34)
    end

    # Make the string magenta
    # @return [String] Magenta string
    def magenta
        colorize(35)
    end

    # Make the string cyan
    # @return [String] Cyan string
    def cyan
        colorize(36)
    end

    # Make the string white
    # @return [String] White string
    def white
        colorize(37)
    end

    # Make the string bold
    # @return [String] Bold string
    def bold
        colorize(1)
    end

    # Make the string gray/grey / light black
    # @return [String] Gray string
    def gray
        colorize(90)
    end
    alias grey gray

    # Make the string light red
    # @return [String] Light red string
    def light_red
        colorize(91)
    end

    # Make the string light green
    # @return [String] Light green string
    def light_green
        colorize(92)
    end

    # Make the string light yellow
    # @return [String] Light yellow string
    def light_yellow
        colorize(93)
    end

    # Make the string light blue
    # @return [String] Light blue string
    def light_blue
        colorize(94)
    end

    # Make the string light magenta
    # @return [String] Light magenta string
    def light_magenta
        colorize(95)
    end

    # Make the string light cyan
    # @return [String] Light cyan string
    def light_cyan
        colorize(96)
    end

    # Make the string light white
    # @return [String] Light white string
    def light_white
        colorize(97)
    end
end
