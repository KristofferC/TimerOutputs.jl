# To make it less likely that users measure TimerOutputs compilation time,
# and to precompile the table rendering pipeline.
let
    to = TimerOutput()
    @timeit to "1" string(1)
    sprint(show, to)
    cto = ConcurrentTimerOutput()
    @timeit cto "1" string(1)
    sprint(show, cto)
end

function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    @assert Base.precompile(Tuple{typeof(print_timer), typeof(stdout), TimerOutput})
    @assert Base.precompile(Tuple{typeof(print_timer), TimerOutput})
    @assert Base.precompile(Tuple{typeof(push!), TimerOutput, String})
    @assert Base.precompile(Tuple{typeof(pop!), TimerOutput})
    @assert Base.precompile(Tuple{typeof(reset_timer!), TimerOutput})
    @assert Base.precompile(Tuple{typeof(disable_timer!), TimerOutput})
    @assert Base.precompile(Tuple{typeof(enable_timer!), TimerOutput})
    @assert Base.precompile(Tuple{typeof(complement!), TimerOutput})
    @assert Base.precompile(Tuple{typeof(do_accumulate!), Metrics, UInt64, Int64})
    @assert Base.precompile(Tuple{typeof(push!), ConcurrentTimerOutput, String})
    @assert Base.precompile(Tuple{typeof(pop!), ConcurrentTimerOutput})
    @assert Base.precompile(Tuple{typeof(register_task_timer!), ConcurrentTimerOutput})
    @assert Base.precompile(Tuple{typeof(merged), ConcurrentTimerOutput})
    @assert Base.precompile(Tuple{typeof(reset_timer!), ConcurrentTimerOutput})
    return @assert Base.precompile(Tuple{Type{TimerOutput}, String})
end
