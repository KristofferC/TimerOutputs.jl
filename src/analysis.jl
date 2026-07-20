#############
# Accessors #
#############

"""
    TimerOutputs.ncalls(x = DEFAULT_TIMER)

The number of times the section was entered.
"""
ncalls(s::Section) = s.ncalls

"""
    TimerOutputs.time(x = DEFAULT_TIMER)

The accumulated time in the section in nanoseconds.
"""
time(s::Section) = s.time

"""
    TimerOutputs.allocated(x = DEFAULT_TIMER)

The accumulated allocations in the section in bytes.
"""
allocated(s::Section) = s.allocs

"""
    TimerOutputs.gctime(x = DEFAULT_TIMER)

The accumulated garbage collection time in the section in nanoseconds.
"""
gctime(s::Section) = s.gc_time

ncalls(to::TimerOutput) = ncalls(to.root)
time(to::TimerOutput) = time(to.root)
allocated(to::TimerOutput) = allocated(to.root)
gctime(to::TimerOutput) = gctime(to.root)

time() = time(DEFAULT_TIMER)
ncalls() = ncalls(DEFAULT_TIMER)
allocated() = allocated(DEFAULT_TIMER)
gctime() = gctime(DEFAULT_TIMER)

# total (time, allocs) covered by the top level sections
function totmeasured(s::Section)
    t, b = Int64(0), Int64(0)
    for child in s.children
        t += child.time
        b += child.allocs
    end
    return t, b
end
function totmeasured(to::TimerOutput)
    measured = to.measured
    measured === nothing || return measured
    return totmeasured(to.root)
end

"""
    TimerOutputs.tottime(x = DEFAULT_TIMER)

Total time in nanoseconds over all sections directly under `x`.
"""
tottime(x) = totmeasured(x)[1]
tottime() = tottime(DEFAULT_TIMER)

"""
    TimerOutputs.totallocated(x = DEFAULT_TIMER)

Total allocated bytes over all sections directly under `x`.
"""
totallocated(x) = totmeasured(x)[2]
totallocated() = totallocated(DEFAULT_TIMER)

############
# Indexing #
############

Base.haskey(s::Section, name::String) = lookup_child(s, name) !== nothing
Base.haskey(to::TimerOutput, name::String) = haskey(to.root, name)
function Base.getindex(s::Section, name::String)
    child = lookup_child(s, name)
    child === nothing && throw(KeyError(name))
    return child
end
Base.getindex(to::TimerOutput, name::String) = to.root[name]

# nested indexing: to["a", "b"] === to["a"]["b"]
Base.getindex(x::Union{TimerOutput, Section}, name::String, rest::String...) = getindex(x[name], rest...)

# section names in insertion order
Base.keys(s::Section) = (child.name for child in s.children)
Base.keys(to::TimerOutput) = keys(to.root)

###########
# Merging #
###########

const merge_lock = ReentrantLock() # merges may happen from different threads

Base.merge(to::TimerOutput, others::TimerOutput...) = merge!(TimerOutput(), to, others...)

function Base.merge!(to::TimerOutput, others::TimerOutput...; tree_point = String[])
    return lock(merge_lock) do
        # If any input carries a `measured` override (as `flatten` sets, where
        # the flattened rows no longer sum to the original total), the merged
        # total is the sum of the inputs' measured totals. Compute it before
        # mutating anything. Without an override it stays derived from children.
        overridden = to.measured !== nothing || any(o -> o.measured !== nothing, others)
        measured = if overridden
            t, b = totmeasured(to)
            for other in others
                ot, ob = totmeasured(other)
                t += ot
                b += ob
            end
            (t, b)
        else
            nothing
        end
        for other in others
            combine!(to.root, other.root)
            # the merged measurement period spans that of the inputs
            to.start_time = min(to.start_time, other.start_time)
            to.start_allocs = min(to.start_allocs, other.start_allocs)
            into = to.root
            for label in tree_point
                into = into[label]
            end
            _merge_children!(into, other.root)
        end
        to.measured = measured
        return to
    end
end

# merge (copies of) the children of `from` into `into`, by label
function _merge_children!(into::Section, from::Section)
    for child in from.children
        existing = lookup_child(into, child.name)
        if existing === nothing
            add_child!(into, copy(child))
        else
            combine!(existing, child)
            _merge_children!(existing, child)
        end
    end
    return into
end

##############
# Flattening #
##############

"""
    TimerOutputs.flatten(to::TimerOutput) -> TimerOutput

Return a new `TimerOutput` where the data for all sections with identical
labels, regardless of nesting level, is accumulated into one flat level.
"""
function flatten(to::TimerOutput)
    flat = TimerOutput("Flattened")
    flat.start_time = to.start_time
    flat.start_allocs = to.start_allocs
    flat.measured = totmeasured(to)
    for child in to.root.children
        _flatten!(flat.root, child)
    end
    return flat
end

function _flatten!(into::Section, s::Section)
    for child in s.children
        _flatten!(into, child)
    end
    existing = lookup_child(into, s.name)
    if existing === nothing
        add_child!(into, copy_node(s))
    else
        combine!(existing, s)
    end
    return into
end

##############
# Complement #
##############

"""
    TimerOutputs.complement!(to::TimerOutput = DEFAULT_TIMER)

Add to each section a `~name~` subsection accounting for the time and
allocations not covered by its subsections.
"""
complement!() = complement!(DEFAULT_TIMER)
function complement!(to::TimerOutput)
    for child in to.root.children
        _complement!(child)
    end
    return to
end

# A detached section holding what is left of `s` when its children are
# subtracted, i.e. the time and allocations in `s` not covered by a nested
# section
function complement_section(s::Section)
    rem_time = s.time
    rem_allocs = s.allocs
    rem_gc = s.gc_time
    for child in s.children
        rem_time -= child.time
        rem_allocs -= child.allocs
        rem_gc -= child.gc_time
    end
    return Section(
        string("~", s.name, "~"), max(1, s.ncalls), max(rem_time, 0), max(rem_allocs, 0),
        max(rem_gc, 0), s.firstexec, Section[], nothing, nothing, true, false, s.srcfile
    )
end

function _complement!(s::Section)
    # `complement!` may be called repeatedly. Remove the previously generated
    # complement before recomputing it so the value reflects measurements
    # accumulated since the previous call. Identify it by its `is_complement`
    # flag, not its label: a user section that happens to be named `~name~`
    # holds real timing data and must not be deleted.
    filter!(child -> !child.is_complement, s.children)
    s.index = length(s.children) > INDEX_THRESHOLD ?
        Dict{String, Section}(child.name => child for child in s.children) : nothing
    if s.prev_child !== nothing && s.prev_child.is_complement
        s.prev_child = nothing
    end

    isempty(s.children) && return
    complement = complement_section(s)
    for child in s.children
        _complement!(child)
    end
    add_child!(s, complement)
    return
end

#################
# Serialization #
#################

"""
    todict(x::Union{TimerOutput, Section}) -> Dict{String, Any}

Converts a timer into a nested set of dictionaries, with keys and value types:

* `"n_calls"`: `Int`
* `"time_ns"`: `Int`
* `"gc_time_ns"`: `Int`
* `"allocated_bytes"`: `Int`
* `"total_allocated_bytes"`: `Int`
* `"total_time_ns"`: `Int`
* `"inner_timers"`: `Dict{String, Dict{String, Any}}`
"""
todict(to::TimerOutput) = todict(to.root)
function todict(s::Section)
    return Dict{String, Any}(
        "n_calls" => ncalls(s),
        "time_ns" => time(s),
        "gc_time_ns" => gctime(s),
        "allocated_bytes" => allocated(s),
        "total_time_ns" => tottime(s),
        "total_allocated_bytes" => totallocated(s),
        "inner_timers" => Dict{String, Any}(c.name => todict(c) for c in s.children)
    )
end

###################
# Manual sections #
###################

struct SectionTimeData
    label::String # not needed for stopping, but useful for debugging
    data::Section
    allocs_start::Int64
    time_start::Int64
    gc_start::Int64
end

"""
    begin_timed_section!([to = DEFAULT_TIMER], label::String)

Start timing a section with the given label. Returns a `SectionTimeData`
object that should be passed to `end_timed_section!` when the section is done.
"""
begin_timed_section!(label::String) = begin_timed_section!(DEFAULT_TIMER, label)
function begin_timed_section!(to::TimerOutput, label::String)
    data = push!(to, label)
    g₀ = gc_time()
    b₀ = gc_bytes()
    t₀ = time_ns()
    return SectionTimeData(label, data, b₀, t₀, g₀)
end

"""
    end_timed_section!([to = DEFAULT_TIMER], section::SectionTimeData)

Stop timing a section started with `begin_timed_section!`.
"""
end_timed_section!(section::SectionTimeData) = end_timed_section!(DEFAULT_TIMER, section)
function end_timed_section!(to::TimerOutput, section::SectionTimeData)
    section.data.time += time_ns() - section.time_start
    section.data.allocs += gc_bytes() - section.allocs_start
    section.data.gc_time += gc_time() - section.gc_start
    section.data.ncalls += 1
    return pop!(to)
end

# the manual section API is also a no-op for NoTimerOutput
begin_timed_section!(::NoTimerOutput, ::String) = nothing
end_timed_section!(::NoTimerOutput, ::Nothing) = nothing

"""
    timeit(f::Function, [to = DEFAULT_TIMER], label::String)

Functional form of `@timeit`: time the call `f()` under `label`.
"""
timeit(f::Function, label::String) = timeit(f, DEFAULT_TIMER, label)
timeit(f::Function, ::NoTimerOutput, ::String) = f()
function timeit(f::Function, to::TimerOutput, label::String)
    isenabled(to) || return f()
    section = begin_timed_section!(to, label)
    local val
    try
        val = f()
    finally
        end_timed_section!(to, section)
    end
    return val
end

##########################
# Instrumented functions #
##########################

# implemented as a callable type to get better error messages
# (i.e. you see `F` explicitly, which might be `typeof(f)` telling
# you that `f` is involved).
struct InstrumentedFunction{F} <: Function
    func::F
    t::TimerOutput
    name::String
    # `name` is a module-qualified function label the printer may shorten
    qualified::Bool
end

# The section label: the module-qualified `repr` so functions of the same name
# from different modules get distinct sections. The printer shows just the final
# component unless siblings would collide (see `qualified`). Construction is cold.
funcname(f) = repr(f)

# Whether `f`'s label is a plain module-qualified identifier (`MyPkg.foo`), safe
# to shorten to its last component for display. Excludes closures/anonymous
# (gensym names), ComposedFunction, Fix*, and callable structs, whose `repr` is
# not a dotted identifier.
shortenable(f) = f isa Function && fieldcount(typeof(f)) == 0 && !startswith(string(nameof(f)), "#")

InstrumentedFunction(f, t, name) = InstrumentedFunction(f, t, name, false)
InstrumentedFunction(f, t) = InstrumentedFunction(f, t, funcname(f), shortenable(f))

function (inst::InstrumentedFunction)(args...; kwargs...)
    to = inst.t
    isenabled(to) || return inst.func(args...; kwargs...)
    data = push!(to, inst.name)
    inst.qualified && (data.qualified = true)
    g₀ = gc_time()
    b₀ = gc_bytes()
    t₀ = time_ns()
    try
        return inst.func(args...; kwargs...)
    finally
        do_accumulate!(data, t₀, b₀, g₀)
        pop!(to)
    end
end

"""
    (t::TimerOutput)(f) -> InstrumentedFunction
    (t::TimerOutput)(f, name::String) -> InstrumentedFunction

Instruments `f` by the [`TimerOutput`](@ref) `t` returning an `InstrumentedFunction`.
This function can be used just like `f`, but whenever it is called it stores timing
results in `t`.

Without an explicit `name`, the section is labeled by `f`'s module-qualified name
but printed as just the final component (e.g. `foo` for `MyPkg.foo`), falling back
to the qualified name if two instrumented functions would otherwise collide. An
explicit `name` is shown verbatim.
"""
(t::TimerOutput)(f) = InstrumentedFunction(f, t)
(t::TimerOutput)(f, name::AbstractString) = InstrumentedFunction(f, t, String(name), false)
