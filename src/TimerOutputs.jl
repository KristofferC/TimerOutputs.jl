module TimerOutputs

import Base: show, time_ns, gc_bytes
export TimerOutput, @timeit, @timer, reset_timer!, print_timer, timeit,
       sortmode!, linemode!, enable_allocations!

using Compat
using Crayons

include("TimerOutput.jl")
include("show.jl")
include("utilities.jl")

end # module
