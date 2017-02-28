module TimerOutputs

import Base: show, time_ns, gc_bytes
export TimerOutput, @timeit, @timer, reset_timer!, print_timer, time_section, enter_section, exit_section,
       sortmode!, linemode!, enable_allocations!

using Compat

macro timeit(args...)
    return timer_expr(args...)
end



BOX_MODE = :unicode
SORT_MODE = :time
ALLOCATIONS_ENABLED = true

function sortmode!(sortmode::Symbol)
    global SORT_MODE
    if sortmode == :time || sortmode == :allocated
        SORT_MODE = sortmode
    else
        throw(ArgumentError("sortmode! accepts :time or :allocated as argument"))
    end
end

function linemode!(linemode::Symbol)
    global BOX_MODE
    if linemode == :unicode || linemode == :ascii
        BOX_MODE = linemode
    else
        throw(ArgumentError("linemode! accepts :unicode or :ascii as argument"))
    end
end

enable_allocations!(doit::Bool) = global ALLOCATIONS_ENABLED = doit


# Default fallback for macro
timer_expr(args...) = throw(ArgumentError("invalid macro usage for @timeit"))

include("TimeData.jl")
include("AbstractTimerOutput.jl")
include("DefaultTimer.jl")
include("TimerOutput.jl")
include("utilities.jl")

end # module
