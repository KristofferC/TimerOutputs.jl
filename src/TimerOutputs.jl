module TimerOutputs

import Base: show, time_ns, gc_bytes
export TimerOutput, @timeit, reset_timer!, print_timer, timeit

using Compat
using Crayons

include("TimerOutput.jl")
include("show.jl")
include("utilities.jl")

end # module
