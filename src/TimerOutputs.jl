module TimerOutputs

using ExprTools: splitdef, combinedef
using Printf: @sprintf
using PrettyTables: pretty_table, MultiColumn, EmptyCells, TextTableFormat, TextTableStyle,
    text_table_borders__compact, @text__no_vertical_lines, @crayon_str
import Tables

import Base: show, time_ns

export TimerOutput, ConcurrentTimerOutput, NoTimerOutput, @timeit, @timeit_debug,
    reset_timer!, print_timer, timeit, enable_timer!, disable_timer!, @notimeit,
    get_timer, begin_timed_section!, end_timed_section!

function gc_bytes()
    b = Ref{Int64}(0)
    Base.gc_bytes(b)
    return b[]
end

include("core.jl")
include("macros.jl")
include("analysis.jl")
include("concurrent.jl")
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
