# To make it less likely that users measure TimerOutputs compilation time.
let
    @timeit "1" string(1)
end

function _precompile_()
  ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
  @assert Base.precompile(Tuple{typeof(print_timer), typeof(stdout), TimerOutput})
  @assert Base.precompile(Tuple{typeof(print_timer), TimerOutput})
  @assert Base.precompile(Tuple{typeof(finish!), TimerOutput, Int, Int})
  @assert Base.precompile(Tuple{typeof(reset_timer!), TimerOutput})
  @assert Base.precompile(Tuple{typeof(register!), TimerOutput})
  @assert Base.precompile(Tuple{Type{TimerOutput}, String, TimerOutput})
end
