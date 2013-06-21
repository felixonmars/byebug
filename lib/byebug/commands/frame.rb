module Byebug

  # Mix-in module to assist in command parsing.
  module FrameFunctions

    def adjust_frame(frame_pos, absolute, context=@state.context)
      @state.frame_pos = 0 if context != @state.context
      if absolute
        if frame_pos < 0
          abs_frame_pos = context.stack_size + frame_pos
        else
          abs_frame_pos = frame_pos
        end
      else
        abs_frame_pos = @state.frame_pos + frame_pos
      end

      if abs_frame_pos >= context.stack_size then
        return \
          errmsg "Adjusting would put us beyond the oldest (initial) frame.\n"
      elsif abs_frame_pos < 0 then
        return \
          errmsg "Adjusting would put us beyond the newest (innermost) frame.\n"
        return
      end

      if @state.frame_pos != abs_frame_pos then
        @state.previous_line = nil
        @state.frame_pos = abs_frame_pos
      end

      @state.file = @state.context.frame_file @state.frame_pos
      @state.line = @state.context.frame_line @state.frame_pos

      print_frame @state.frame_pos, false
    end

    def get_frame_call(prefix, pos)
      id = @state.context.frame_method(pos)
      return "<main>" unless id

      klass = @state.context.frame_class(pos)

      if Command.settings[:callstyle] != :short && klass
        call_str = "#{klass}.#{id.id2name}"
      else
        call_str = "#{id.id2name}"
      end

      args = @state.context.frame_args pos
      locals = @state.context.frame_locals pos
      if args.any?
        call_str += "("
        args.each_with_index do |name, i|
          case Command.settings[:callstyle]
          when :short
            call_str += "#{name}, "
          when :last
            klass = locals[name].class
            if klass.inspect.size > 20 + 3
              klass = klass.inspect[0..20] + "..."
            end
            call_str += "#{name}##{klass}, "
          when :tracked
            arg_info = context.frame_args_info pos
            if arg_info && arg_info.size > i
              call_str += "#{name}: #{arg_info[i].inspect}, "
            else
              call_str += "#{name}, "
            end
          end
          if call_str.size > Command.settings[:width] - prefix.size
            # Strip off trailing ', ' if any but add stuff for later trunc
            call_str[-2..-1] = ",...XX"
            break
          end
        end
        call_str[-2..-1] = ")" # Strip off trailing ', ' if any
      end
      return call_str
    end

    def print_backtrace
      (0...@state.context.stack_size).each do |idx|
        print_frame(idx)
      end
    end

    def print_frame(pos, mark_current = true)
      file = @state.context.frame_file pos
      line = @state.context.frame_line pos

      unless Command.settings[:frame_fullpath]
        path_components = file.split(/[\\\/]/)
        if path_components.size > 3
          path_components[0...-3] = '...'
          file = path_components.join(File::ALT_SEPARATOR || File::SEPARATOR)
        end
      end

      if mark_current
        frame_str = (pos == @state.frame_pos) ? "--> " : "    "
      else
        frame_str = ""
      end

      frame_str += sprintf "#%-2d ", pos
      frame_str += get_frame_call frame_str, pos
      file_line = "at #{CommandProcessor.canonic_file(file)}:#{line}"
      if frame_str.size + file_line.size + 1 > Command.settings[:width]
        frame_str += "\n      #{file_line}\n"
      else
        frame_str += " #{file_line}\n"
      end

      print frame_str
    end
  end

  # Implements byebug "where" or "backtrace" command.
  class WhereCommand < Command
    def regexp
      /^\s*(?:w(?:here)?|bt|backtrace)$/
    end

    def execute
      print_backtrace
    end

    class << self
      def names
        %w(where backtrace)
      end

      def description
        %{w[here]|bt|backtrace\tdisplay stack frames

          Print the entire stack frame. Each frame is numbered, the most recent
          frame is 0. frame number can be referred to in the "frame" command;
          "up" and "down" add or subtract respectively to frame numbers shown.
          The position of the current frame is marked with -->.}
      end
    end
  end

  class UpCommand < Command
    def regexp
      /^\s* u(?:p)? (?:\s+(.*))?$/x
    end

    def execute
      pos = get_int(@match[1], "Up")
      return unless pos
      adjust_frame(pos, false)
    end

    class << self
      def names
        %w(up)
      end

      def description
        %{up[ count]\tmove to higher frame}
      end
    end
  end

  class DownCommand < Command
    def regexp
      /^\s* down (?:\s+(.*))? .*$/x
    end

    def execute
      pos = get_int(@match[1], "Down")
      return unless pos
      adjust_frame(-pos, false)
    end

    class << self
      def names
        %w(down)
      end

      def description
        %{down[ count]\tmove to lower frame}
      end
    end
  end

  class FrameCommand < Command
    def regexp
      / ^\s*
        f(?:rame)?
        (?: \s+ (\S+))? \s*
        $/x
    end

    def execute
      if not @match[1]
        pos = 0
      else
        pos = get_int(@match[1], "Frame")
        return unless pos
      end
      adjust_frame(pos, true)
    end

    class << self
      def names
        %w(frame)
      end

      def description
        %{f[rame][ frame-number]

          Move the current frame to the specified frame number, or the 0 if no
          frame-number has been given.

          A negative number indicates position from the other end, so "frame -1"
          moves to the oldest frame, and "frame 0" moves to the newest frame.

          Without an argument, the command prints the current stack frame. Since
          the current position is redisplayed, it may trigger a resyncronization
          if there is a front end also watching over things.}
      end
    end
  end
end
