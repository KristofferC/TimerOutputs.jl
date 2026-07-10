#############
# Accessors #
#############

"""
    TimerOutputs.ncalls(x = DEFAULT_TIMER)

The number of times the section was entered.
"""
ncalls(s::Section) = s.metrics.ncalls

"""
    TimerOutputs.time(x = DEFAULT_TIMER)

The accumulated time in the section in nanoseconds.
"""
time(s::Section) = s.metrics.time

"""
    TimerOutputs.allocated(x = DEFAULT_TIMER)

The accumulated allocations in the section in bytes.
"""
allocated(s::Section) = s.metrics.allocs

ncalls(to::TimerOutput) = ncalls(to.root)
time(to::TimerOutput) = time(to.root)
allocated(to::TimerOutput) = allocated(to.root)

time() = time(DEFAULT_TIMER)
ncalls() = ncalls(DEFAULT_TIMER)
allocated() = allocated(DEFAULT_TIMER)

# total (time, allocs) covered by the top level sections
function totmeasured(s::Section)
    t, b = Int64(0), Int64(0)
    for child in values(s.children)
        t += child.metrics.time
        b += child.metrics.allocs
    end
    return t, b
end
function totmeasured(to::TimerOutput)
    to.measured === nothing || return to.measured
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

Base.haskey(s::Section, name::String) = haskey(s.children, name)
Base.haskey(to::TimerOutput, name::String) = haskey(to.root, name)
Base.getindex(s::Section, name::String) = s.children[name]
Base.getindex(to::TimerOutput, name::String) = to.root[name]

# nested indexing: to["a", "b"] === to["a"]["b"]
Base.getindex(x::Union{TimerOutput, Section}, name::String, rest::String...) = getindex(x[name], rest...)

Base.keys(s::Section) = keys(s.children)
Base.keys(to::TimerOutput) = keys(to.root)

###########
# Merging #
###########

const merge_lock = ReentrantLock() # merges may happen from different threads

Base.merge(to::TimerOutput, others::TimerOutput...) = merge!(TimerOutput(), to, others...)

function Base.merge!(to::TimerOutput, others::TimerOutput...; tree_point = String[])
    return lock(merge_lock) do
        for other in others
            combine!(to.root.metrics, other.root.metrics)
            # the merged measurement period spans that of the inputs
            to.start_time = min(to.start_time, other.start_time)
            to.start_allocs = min(to.start_allocs, other.start_allocs)
            into = to.root
            for label in tree_point
                into = into[label]
            end
            _merge!(into.children, other.root.children)
        end
        return to
    end
end

function _merge!(into::Dict{String, Section}, from::Dict{String, Section})
    for (label, section) in from
        existing = get(into, label, nothing)
        if existing === nothing
            into[label] = copy(section)
        else
            combine!(existing.metrics, section.metrics)
            _merge!(existing.children, section.children)
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
    for child in values(to.root.children)
        _flatten!(flat.root.children, child)
    end
    return flat
end

function _flatten!(into::Dict{String, Section}, s::Section)
    for child in values(s.children)
        _flatten!(into, child)
    end
    existing = get(into, s.name, nothing)
    if existing === nothing
        into[s.name] = copy_node(s)
    else
        combine!(existing.metrics, s.metrics)
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
    for child in values(to.root.children)
        _complement!(child)
    end
    return to
end

function _complement!(s::Section)
    isempty(s.children) && return
    rem_time = s.metrics.time
    rem_allocs = s.metrics.allocs
    for child in values(s.children)
        rem_time -= child.metrics.time
        rem_allocs -= child.metrics.allocs
        _complement!(child)
    end
    name = string("~", s.name, "~")
    metrics = Metrics(max(1, s.metrics.ncalls), max(rem_time, 0), max(rem_allocs, 0), s.metrics.firstexec)
    s.children[name] = Section(name, metrics, Dict{String, Section}(), nothing, nothing)
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
        "allocated_bytes" => allocated(s),
        "total_time_ns" => tottime(s),
        "total_allocated_bytes" => totallocated(s),
        "inner_timers" => Dict{String, Any}(k => todict(v) for (k, v) in s.children)
    )
end

###################
# Manual sections #
###################

struct SectionTimeData
    label::String # not needed for stopping, but useful for debugging
    data::Metrics
    allocs_start::Int64
    time_start::Int64
end

"""
    begin_timed_section!([to = DEFAULT_TIMER], label::String)

Start timing a section with the given label. Returns a `SectionTimeData`
object that should be passed to `end_timed_section!` when the section is done.
"""
begin_timed_section!(label::String) = begin_timed_section!(DEFAULT_TIMER, label)
function begin_timed_section!(to::TimerOutput, label::String)
    data = push!(to, label)
    b₀ = gc_bytes()
    t₀ = time_ns()
    return SectionTimeData(label, data, b₀, t₀)
end

"""
    end_timed_section!([to = DEFAULT_TIMER], section::SectionTimeData)

Stop timing a section started with `begin_timed_section!`.
"""
end_timed_section!(section::SectionTimeData) = end_timed_section!(DEFAULT_TIMER, section)
function end_timed_section!(to::TimerOutput, section::SectionTimeData)
    section.data.time += time_ns() - section.time_start
    section.data.allocs += gc_bytes() - section.allocs_start
    section.data.ncalls += 1
    return pop!(to)
end

"""
    timeit(f::Function, [to = DEFAULT_TIMER], label::String)

Functional form of `@timeit`: time the call `f()` under `label`.
"""
timeit(f::Function, label::String) = timeit(f, DEFAULT_TIMER, label)
function timeit(f::Function, to::TimerOutput, label::String)
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
end

function funcname(f::F) where {F}
    return if @generated
        string(repr(F.instance))
    else
        string(repr(f))
    end
end

InstrumentedFunction(f, t) = InstrumentedFunction(f, t, funcname(f))

function (inst::InstrumentedFunction)(args...; kwargs...)
    return @timeit inst.t inst.name inst.func(args...; kwargs...)
end

"""
    (t::TimerOutput)(f, name=string(repr(f))) -> InstrumentedFunction

Instruments `f` by the [`TimerOutput`](@ref) `t` returning an `InstrumentedFunction`.
This function can be used just like `f`, but whenever it is called it stores timing
results in `t`.
"""
(t::TimerOutput)(f, name = funcname(f)) = InstrumentedFunction(f, t, name)
