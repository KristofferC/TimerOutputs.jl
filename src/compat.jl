########################################
# Bridges for pre-0.6 API / internals  #
########################################

Base.@deprecate get_defaultimer get_defaulttimer

# Pre-0.6, the tree nodes were TimerOutput objects holding a TimeData in
# `accumulated_data` and their children in an `inner_timers` Dict. Keep the
# commonly poked names readable. A `Section` itself carries the old TimeData
# field names (ncalls, time, allocs, firstexec), so it stands in for
# `accumulated_data`; `inner_timers` materializes a fresh Dict.
function Base.getproperty(to::TimerOutput, f::Symbol)
    f === :inner_timers && return _inner_timers(getfield(to, :root))
    f === :accumulated_data && return getfield(to, :root)
    f === :name && return getfield(getfield(to, :root), :name)
    f === :timer_stack && return getfield(to, :stack)
    f === :flattened && return getfield(to, :measured) !== nothing
    return getfield(to, f)
end

function Base.getproperty(s::Section, f::Symbol)
    f === :inner_timers && return _inner_timers(s)
    f === :accumulated_data && return s
    return getfield(s, f)
end

function _inner_timers(s::Section)
    children = getfield(s, :children)
    return Dict{String, Section}(getfield(c, :name) => c for c in children)
end
