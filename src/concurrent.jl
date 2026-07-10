#########################
# ConcurrentTimerOutput #
#########################

"""
    ConcurrentTimerOutput()

A timer that, unlike `TimerOutput`, can be used from multiple tasks (and
therefore threads) concurrently. Each task transparently records into its own
private timer tree; the trees are combined by label whenever the timer is
displayed or queried.

Semantics: the time reported for a section is the sum of the wall clock time
every task spent inside it (including time where the task was not scheduled),
so with parallelism the measured percentage can exceed 100%. Queries like
`getindex` and `TimerOutput(cto)` return detached snapshot copies; snapshots
taken while sections are in flight are approximately consistent and become
exact once the tasks quiesce.
"""
mutable struct ConcurrentTimerOutput
    @atomic enabled::Bool
    @atomic generation::Int # bumped by reset_timer!
    const lock::ReentrantLock
    const task_timers::Vector{Tuple{WeakRef, TimerOutput}} # (task, its private tree); guarded by lock
    archive::TimerOutput # merged trees of finished tasks; canonical start time; guarded by lock
end

function ConcurrentTimerOutput()
    return ConcurrentTimerOutput(true, 0, ReentrantLock(), Tuple{WeakRef, TimerOutput}[], TimerOutput())
end

isenabled(cto::ConcurrentTimerOutput) = @atomic :monotonic cto.enabled
enable_timer!(cto::ConcurrentTimerOutput) = @atomic cto.enabled = true
disable_timer!(cto::ConcurrentTimerOutput) = @atomic cto.enabled = false

# The value stored in task local storage, keyed by the ConcurrentTimerOutput
struct TaskTimerEntry
    generation::Int
    timer::TimerOutput
end

# Hot path: fetch the calling task's private timer (~3 ns)
@inline function task_timer(cto::ConcurrentTimerOutput)
    entry = get(task_local_storage(), cto, nothing)
    if entry isa TaskTimerEntry && entry.generation == (@atomic :monotonic cto.generation)
        return entry.timer
    end
    return register_task_timer!(cto)
end

# Slow path, once per task (and generation). Everything happens under the lock
# so that a timer can never be registered under a stale generation.
@noinline function register_task_timer!(cto::ConcurrentTimerOutput)
    return lock(cto.lock) do
        timer = TimerOutput()
        push!(cto.task_timers, (WeakRef(current_task()), timer))
        task_local_storage()[cto] = TaskTimerEntry(@atomic(cto.generation), timer)
        timer
    end
end

# Inserting a new label must take the lock: `merged` may be iterating this
# task's children from another task while we mutate them. Runs once per
# distinct label per task. A function instead of a `lock() do` closure in
# push! to avoid boxing in the hot path there.
@noinline function locked_insert!(cto::ConcurrentTimerOutput, parent::Section, label::String)
    section = Section(label)
    lock(cto.lock)
    try
        add_child!(parent, section)
    finally
        unlock(cto.lock)
    end
    return section
end

# Same as push!(::TimerOutput, label) except for the locked insert of new
# labels. The steady state paths are lock-free.
function Base.push!(cto::ConcurrentTimerOutput, label::String)
    to = task_timer(cto)
    parent = current_section(to)
    prev = parent.prev_child
    if prev !== nothing && prev.name == label
        section = prev
    else
        section = lookup_child(parent, label)
        if section === nothing
            section = locked_insert!(cto, parent, label)
        end
    end
    section = section::Section
    parent.prev_child = section

    push!(to.stack, section)
    return section
end

# Deliberately does not check the generation: if reset_timer! happened while a
# section was in flight, its cleanup must still unwind the (orphaned) tree it
# started in instead of registering a fresh one.
function Base.pop!(cto::ConcurrentTimerOutput)
    entry = get(task_local_storage(), cto, nothing)
    entry isa TaskTimerEntry || return nothing
    return pop!(entry.timer)
end

function reset_timer!(cto::ConcurrentTimerOutput)
    lock(cto.lock) do
        @atomic cto.generation += 1
        empty!(cto.task_timers)
        cto.archive = TimerOutput()
    end
    return cto
end

"""
    TimerOutput(cto::ConcurrentTimerOutput) -> TimerOutput

Combine the per-task timer trees of `cto` into a single detached `TimerOutput`
snapshot, merging sections with the same label and nesting.
"""
TimerOutput(cto::ConcurrentTimerOutput) = merged(cto)

function merged(cto::ConcurrentTimerOutput)
    return lock(cto.lock) do
        # fold the trees of finished tasks into the archive and drop them,
        # bounding memory when many short-lived tasks are timed
        filter!(cto.task_timers) do (ref, timer)
            task = ref.value
            if task === nothing || istaskdone(task::Task)
                combine!(cto.archive.root, timer.root)
                _merge_children!(cto.archive.root, timer.root)
                false
            else
                true
            end
        end
        # `copy` reads only names, counters and children, never the prev_child
        # cache the owning task may be mutating; counter reads of in-flight
        # sections are approximately consistent (documented)
        archive = cto.archive
        result = TimerOutput(copy(archive.root), Section[], true, archive.start_time, archive.start_allocs, nothing)
        for (_, timer) in cto.task_timers
            combine!(result.root, timer.root)
            _merge_children!(result.root, timer.root)
        end
        result
    end
end

# Sections started manually
function begin_timed_section!(cto::ConcurrentTimerOutput, label::String)
    data = push!(cto, label)
    b₀ = gc_bytes()
    t₀ = time_ns()
    return SectionTimeData(label, data, b₀, t₀)
end

function end_timed_section!(cto::ConcurrentTimerOutput, section::SectionTimeData)
    section.data.time += time_ns() - section.time_start
    section.data.allocs += gc_bytes() - section.allocs_start
    section.data.ncalls += 1
    return pop!(cto)
end

function timeit(f::Function, cto::ConcurrentTimerOutput, label::String)
    section = begin_timed_section!(cto, label)
    local val
    try
        val = f()
    finally
        end_timed_section!(cto, section)
    end
    return val
end

# Queries and display all work on a merged snapshot
ncalls(cto::ConcurrentTimerOutput) = ncalls(merged(cto))
allocated(cto::ConcurrentTimerOutput) = allocated(merged(cto))
time(cto::ConcurrentTimerOutput) = time(merged(cto))
totallocated(cto::ConcurrentTimerOutput) = totallocated(merged(cto))
tottime(cto::ConcurrentTimerOutput) = tottime(merged(cto))
todict(cto::ConcurrentTimerOutput) = todict(merged(cto))
flatten(cto::ConcurrentTimerOutput) = flatten(merged(cto))
Base.haskey(cto::ConcurrentTimerOutput, name::String) = haskey(merged(cto), name)
Base.getindex(cto::ConcurrentTimerOutput, name::String) = merged(cto)[name]
Base.keys(cto::ConcurrentTimerOutput) = keys(merged(cto))

function complement!(::ConcurrentTimerOutput)
    throw(ArgumentError("complement! mutates a timer in place; use complement!(TimerOutput(cto)) on a snapshot"))
end

Base.merge!(to::TimerOutput, cto::ConcurrentTimerOutput; kwargs...) = merge!(to, merged(cto); kwargs...)
function Base.merge!(cto::ConcurrentTimerOutput, others::TimerOutput...)
    lock(cto.lock) do
        archive = cto.archive
        for other in others
            combine!(archive.root, other.root)
            # the merged measurement period spans that of the inputs
            archive.start_time = min(archive.start_time, other.start_time)
            archive.start_allocs = min(archive.start_allocs, other.start_allocs)
            _merge_children!(archive.root, other.root)
        end
    end
    return cto
end
