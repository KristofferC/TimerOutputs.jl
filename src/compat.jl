########################################
# Bridges for pre-0.6 API / internals  #
########################################

# The 0.5 node type was called TimeData
const TimeData = Metrics

Base.@deprecate get_defaultimer get_defaulttimer

# Pre-0.6, the tree nodes were TimerOutput objects with these fields. Keep the
# commonly poked ones readable; they constant-fold to plain field access.
function Base.getproperty(to::TimerOutput, f::Symbol)
    f === :inner_timers && return getfield(getfield(to, :root), :children)
    f === :accumulated_data && return getfield(getfield(to, :root), :metrics)
    f === :name && return getfield(getfield(to, :root), :name)
    f === :timer_stack && return getfield(to, :stack)
    f === :flattened && return getfield(to, :measured) !== nothing
    return getfield(to, f)
end

function Base.getproperty(s::Section, f::Symbol)
    f === :inner_timers && return getfield(s, :children)
    f === :accumulated_data && return getfield(s, :metrics)
    return getfield(s, f)
end
