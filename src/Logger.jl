# Constructors

mutable struct LogBuffer
  events::Array{Event}
end


log_buffer = LogBuffer([])
log_categories = Dict(:injects => String[], :props => String[], :kills => String[], :gens => String[])

stack_trace_lines = String[]


function log_event(evt::Event)
  push!(log_buffer.events, evt)

  if ft_config.log.printToStdOut
    println(to_string(evt))
  end
  if length(log_buffer.events) >= ft_config.log.buffersize
    if isa(ft_config.log.maxLogs, Unbounded) || (isa(ft_config.log.maxLogs, Int) && ft_config.log.maxLogs > 0)
      ft_flush_logs()
      if isa(ft_config.log.maxLogs, Int)
        ft_config.log.maxLogs -= length(log_buffer.events)
      end
    end
    log_buffer.events = []
  end
end

function ft_flush_logs()
  if ft_config.log.allErrors
    write_error_logs()
  end

  if ft_config.log.cstg
    write_logs_for_cstg()
  end
end

function print_log()
  for e in log_buffer.events
    println(e)
  end
end

function write_error_logs()
  if length(log_buffer.events) > 0
    open(errors_file(), "a") do file
      for e in log_buffer.events
        write(file, "$(to_string(e))\n\n")
      end
    end
  end
end


function write_logs_for_cstg()
  injects  = filter(e -> e.evt_type == :injected, log_buffer.events)
  gens     = filter(e -> e.evt_type == :gen, log_buffer.events)
  props    = filter(e -> e.evt_type == :prop, log_buffer.events)
  kills    = filter(e -> e.evt_type == :kill, log_buffer.events)

   # Update to use the log_categories dictionary
  if length(injects) > 0
    write_events("injects", injects)
  end
  if length(gens) > 0
      write_events("gens", gens)
  end
  if length(props) > 0
      write_events("props", props)
  end
  if length(kills) > 0
      write_events("kills", kills)
  end
end

function format_cstg_stackframe(sf::StackTraces.StackFrame, frame_args::Vector{} = [])
  func = String(sf.func)        # FIXME/TODO: can we make sure the function name here is well-formed for CSTG's digestion?
  linfo = "$(sf.linfo)"
  args = if ft_config.log.cstgArgs && isempty(frame_args)
    if isa(sf.linfo, Core.CodeInfo)
      "$(sf.linfo.code[1])"
    else
      mx = match(r"^.+\((.*?)\)", linfo)
      "($(!isnothing(mx) && length(mx) > 0 ? mx[1] : ""))"
    end
  elseif ft_config.log.cstgArgs
    "($frame_args)"
  else
    ""
  end

  linenum = if ft_config.log.cstgLineNum
    ":$(sf.line)"
  else
    ""
  end

  "$(func)$(args) at $(sf.file)$(linenum)"
end

function category(e::Event)
  if e.category == :nan
    "NaN"
  elseif e.category == :inf
    "Inf"
  else
    ""
  end
end


function write_events(category_name, events::Vector{Event})
  for e in events
      if length(e.trace) > 0
          push!(stack_trace_lines, "[$(category(e))] $(format_cstg_stackframe(e.trace[1], e.args))")
          push!(stack_trace_lines, "\n")
          # write remaining frames up to ftv-config.log.maxFrames
          for sf in e.trace[2:(isa(ft_config.log.maxFrames, Unbounded) ? end : (2:(ft_config.log.maxFrames + 1)))]
              push!(stack_trace_lines, "$(format_cstg_stackframe(sf))")
              push!(stack_trace_lines, "\n")
          end

          push!(stack_trace_lines, "\n")

          # Update to store logs in the appropriate category
          push!(log_categories[Symbol(category_name)], join(stack_trace_lines))
          # stack_trace_lines=""
          empty!(stack_trace_lines)
      end
  end
end

# Function to get the logs for a specific category or all categories
function get_stack_traces()
  return log_categories
end
