module TimerOutputs

import Base: show, time_ns
export TimerOutput, @timeit, @timeit_debug, reset_timer!, print_timer, timeit

# https://github.com/JuliaLang/julia/pull/33717
if VERSION < v"1.4.0-DEV.475"
    gc_bytes() = Base.gc_bytes()
else
    function gc_bytes()
        b = Ref{Int64}(0)
        Base.gc_bytes(b)
        return b[]
    end
end

using Printf


include("TimerOutput.jl")
include("show.jl")
include("utilities.jl")

end # module
