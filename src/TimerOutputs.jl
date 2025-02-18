module TimerOutputs

using ExprTools

import Base: show, time_ns
export TimerOutput, @timeit, @timeit_debug, reset_timer!, print_timer, timeit,
                    enable_timer!, disable_timer!, @notimeit, get_timer,
                    start_timed_section!, stop_timed_section!


function gc_bytes()
    b = Ref{Int64}(0)
    Base.gc_bytes(b)
    return b[]
end

using Printf


include("TimerOutput.jl")
include("show.jl")
include("utilities.jl")

include("compile.jl")
_precompile_()

function __init__()
    # Reset DEFAULT_TIMER; otherwise starting time is the time of precompile
    reset_timer!()
end

end # module
