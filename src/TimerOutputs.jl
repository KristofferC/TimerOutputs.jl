__precompile__()

module TimerOutputs

import Base: show, time_ns, gc_bytes
export TimerOutput, @timeit, reset_timer!, print_timer, timeit

using Crayons
using Printf
using Unicode


include("TimerOutput.jl")
include("show.jl")
include("utilities.jl")

end # module
