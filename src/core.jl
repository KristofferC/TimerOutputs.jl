###########
# Metrics #
###########

# Accumulated measurements for one section.
mutable struct Metrics
    ncalls::Int64
    time::Int64      # ns
    allocs::Int64    # bytes
    firstexec::Int64 # time_ns() timestamp of when the section was first entered
end

Metrics() = Metrics(0, 0, 0, time_ns())
Base.copy(m::Metrics) = Metrics(m.ncalls, m.time, m.allocs, m.firstexec)

function combine!(a::Metrics, b::Metrics)
    a.ncalls += b.ncalls
    a.time += b.time
    a.allocs += b.allocs
    a.firstexec = min(a.firstexec, b.firstexec)
    return a
end

# The macro-generated cleanup calls this with the timestamps taken at section entry
@inline function do_accumulate!(m::Metrics, t₀, b₀)
    m.time += time_ns() - t₀
    m.allocs += gc_bytes() - b₀
    m.ncalls += 1
    return m
end

###########
# Section #
###########

# A node in the section tree.
mutable struct Section
    const name::String
    const metrics::Metrics
    const children::Dict{String, Section}
    # cache of the most recently entered child; hit when the same label repeats
    prev_label::Union{String, Nothing}
    prev_child::Union{Section, Nothing}
end

Section(name::String) = Section(name, Metrics(), Dict{String, Section}(), nothing, nothing)

# Copy of a single node without its children
copy_node(s::Section) = Section(s.name, copy(s.metrics), Dict{String, Section}(), nothing, nothing)

function Base.copy(s::Section)
    c = copy_node(s)
    for (k, v) in s.children
        c.children[k] = copy(v)
    end
    return c
end

# The child of `parent` named `label`, created on first use
function child_section(parent::Section, label::String)
    if parent.prev_label == label
        return parent.prev_child::Section
    end
    child = get(parent.children, label, nothing)
    if child === nothing
        child = Section(label)
        parent.children[label] = child
    end
    child = child::Section
    parent.prev_label = label
    parent.prev_child = child
    return child
end

###############
# TimerOutput #
###############

"""
    TimerOutput(name::String = "root")

The main timer type. Time sections of code with `@timeit to "label" ...`;
print the accumulated table with `print_timer(to)` or `show`.

A `TimerOutput` must only be used from one task at a time, see
[`ConcurrentTimerOutput`](@ref) for concurrent code.
"""
mutable struct TimerOutput
    const root::Section
    const stack::Vector{Section} # currently open sections, innermost last
    enabled::Bool
    start_time::Int64   # time_ns() at creation/reset, for the table header
    start_allocs::Int64
    measured::Union{Nothing, Tuple{Int64, Int64}} # (time, allocs) override used by flatten
end

function TimerOutput(name::String = "root")
    return TimerOutput(Section(name), Section[], true, time_ns(), gc_bytes(), nothing)
end

function Base.copy(to::TimerOutput)
    return TimerOutput(copy(to.root), Section[], to.enabled, to.start_time, to.start_allocs, to.measured)
end

current_section(to::TimerOutput) = isempty(to.stack) ? to.root : @inbounds to.stack[end]

# push!/pop! open and close a section; the returned Metrics is what the
# matching cleanup accumulates into
function Base.push!(to::TimerOutput, label::String)
    section = child_section(current_section(to), label)
    push!(to.stack, section)
    return section.metrics
end

# The stack may be empty if `reset_timer!` was called inside a timed section
Base.pop!(to::TimerOutput) = isempty(to.stack) ? nothing : pop!(to.stack)

# What the @timeit macro checks; the generic fallback keeps any timer-like
# object with an `enabled` field working
@inline isenabled(x) = x.enabled

enable_timer!(to::TimerOutput = DEFAULT_TIMER) = to.enabled = true
disable_timer!(to::TimerOutput = DEFAULT_TIMER) = to.enabled = false

reset_timer!() = reset_timer!(DEFAULT_TIMER)
function reset_timer!(to::TimerOutput)
    root = to.root
    empty!(root.children)
    root.prev_label = nothing
    root.prev_child = nothing
    m = root.metrics
    m.ncalls = 0; m.time = 0; m.allocs = 0; m.firstexec = time_ns()
    empty!(to.stack)
    to.start_time = time_ns()
    to.start_allocs = gc_bytes()
    to.measured = nothing
    return to
end

#################
# Default timer #
#################

const DEFAULT_TIMER = TimerOutput()
const _timers = Dict{String, TimerOutput}("Default" => DEFAULT_TIMER)
const _timers_lock = ReentrantLock() # timers can be created from different threads

"""
    get_timer(name::String)

Returns the `TimerOutput` associated with `name`.
If no timers are associated with `name`, a new `TimerOutput` will be created.
"""
function get_timer(name::String)
    return lock(_timers_lock) do
        get!(() -> TimerOutput(name), _timers, name)
    end
end

get_defaulttimer() = DEFAULT_TIMER
