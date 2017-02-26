module TimerOutputs

import Base: show, time_ns
export TimerOutput, @timeit, @timer, reset_timer!, print_timer, time_section, enter_section, exit_section

using Compat

macro timeit(args...)
    return timer_expr(args...)
end

# Default fallback for macro
timer_expr(args...) = throw(ArgumentError("invalid macro usage for @timeit"))

include("TimeData.jl")
include("AbstractTimerOutput.jl")
include("DefaultTimer.jl")
include("TimerOutput.jl")

end # module
