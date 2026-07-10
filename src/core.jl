###########
# Section #
###########

# A node in the section tree. The accumulated measurements are stored inline;
# children are stored in insertion order and scanned linearly (typical fanout
# is small and labels are usually interned literals, making the scan a couple
# of pointer compares), with a Dict index built once the fanout grows.
mutable struct Section
    const name::String
    ncalls::Int64
    time::Int64      # ns
    allocs::Int64    # bytes
    firstexec::Int64 # time_ns() timestamp of when the section was first entered
    const children::Vector{Section}
    index::Union{Dict{String, Section}, Nothing}
    # cache of the most recently entered child; hit when the same label repeats
    prev_child::Union{Section, Nothing}
end

Section(name::String) = Section(name, 0, 0, 0, time_ns(), Section[], nothing, nothing)

# label strings are usually the same interned literal, so try pointer equality first
@inline fasteq(a::String, b::String) = a === b || a == b

const INDEX_THRESHOLD = 8

@inline function lookup_child(parent::Section, label::String)
    index = parent.index
    index === nothing || return get(index, label, nothing)
    for child in parent.children
        fasteq(child.name, label) && return child
    end
    return nothing
end

function add_child!(parent::Section, child::Section)
    push!(parent.children, child)
    index = parent.index
    if index !== nothing
        index[child.name] = child
    elseif length(parent.children) > INDEX_THRESHOLD
        parent.index = Dict{String, Section}(c.name => c for c in parent.children)
    end
    return child
end

@noinline new_child!(parent::Section, label::String) = add_child!(parent, Section(label))

# The child of `parent` named `label`, created on first use
function child_section(parent::Section, label::String)
    prev = parent.prev_child
    if prev !== nothing && fasteq(prev.name, label)
        return prev
    end
    child = lookup_child(parent, label)
    if child === nothing
        child = new_child!(parent, label)
    end
    parent.prev_child = child
    return child
end

# The macro-generated cleanup calls this with the timestamps taken at section entry
@inline function do_accumulate!(s::Section, t₀, b₀)
    s.time += time_ns() - t₀
    s.allocs += gc_bytes() - b₀
    s.ncalls += 1
    return s
end

function combine!(a::Section, b::Section)
    a.ncalls += b.ncalls
    a.time += b.time
    a.allocs += b.allocs
    a.firstexec = min(a.firstexec, b.firstexec)
    return a
end

# Copy of a single node without its children
function copy_node(s::Section)
    return Section(s.name, s.ncalls, s.time, s.allocs, s.firstexec, Section[], nothing, nothing)
end

function Base.copy(s::Section)
    c = copy_node(s)
    for child in s.children
        add_child!(c, copy(child))
    end
    return c
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

# push!/pop! open and close a section; the returned Section is what the
# matching cleanup accumulates into
function Base.push!(to::TimerOutput, label::String)
    section = child_section(current_section(to), label)
    push!(to.stack, section)
    return section
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
    root.index = nothing
    root.prev_child = nothing
    root.ncalls = 0
    root.time = 0
    root.allocs = 0
    root.firstexec = time_ns()
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
