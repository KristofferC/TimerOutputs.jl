module TimerOutputs

using ExprTools: splitdef, combinedef
using Printf: @sprintf
using PrettyTables: pretty_table, MultiColumn, EmptyCells, TextTableFormat, TextTableStyle,
    TextHighlighter, text_table_borders__compact, @text__no_vertical_lines, @crayon_str, Crayon
import Tables

import Base: show, time_ns

export TimerOutput, NoTimerOutput, @timeit, @timeit_debug, @timeit_all, @timed_testset,
    reset_timer!, print_timer, timeit, enable_timer!, disable_timer!, @notimeit,
    get_timer, begin_timed_section!, end_timed_section!

function gc_bytes()
    b = Ref{Int64}(0)
    Base.gc_bytes(b)
    return b[]
end

# cumulative time spent in GC, in ns; sections record the delta over their extent
gc_time() = Base.gc_time_ns()

include("core.jl")
include("macros.jl")
include("analysis.jl")
include("tables.jl")
include("printing.jl")
include("compat.jl")

include("precompile.jl")
_precompile_()

function __init__()
    # Reset DEFAULT_TIMER; otherwise starting time is the time of precompile
    reset_timer!()
    return
end

end # module
