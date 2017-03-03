module TimerOutputs

import Base: show, time_ns, gc_bytes
export TimerOutput, @timeit, @timer, reset_timer!, print_timer, timeit,
       sortmode!, linemode!, enable_allocations!

using Compat
using Crayons



BOX_MODE = :unicode
SORT_MODE = :time
ALLOCATIONS_ENABLED = true

function sortmode!(sortmode::Symbol)
    global SORT_MODE
    if sortmode in (:time, :ncalls, :allocated)
        SORT_MODE = sortmode
    else
        throw(ArgumentError("sortmode! accepts :time or :allocated as argument"))
    end
end

function linemode!(linemode::Symbol)
    global BOX_MODE
    if linemode in (:unicode, :ascii)
        BOX_MODE = linemode
    else
        throw(ArgumentError("linemode! accepts :unicode or :ascii as argument"))
    end
end

enable_allocations!(doit::Bool) = global ALLOCATIONS_ENABLED = doit


include("TimerOutput.jl")
include("show.jl")
include("utilities.jl")

end # module
