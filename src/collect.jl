collect_timings(kwargs...) = collect_timings(DEFAULT_TIMER; kwargs...)

function sortf(x, sortby)
    sortby == :time        && return x.accumulated_data.time
    sortby == :ncalls      && return x.accumulated_data.ncalls
    sortby == :allocations && return x.accumulated_data.allocs
    sortby == :name        && return x.name
    error("internal error")
end

function collect_timings(to::TimerOutput; sortby::Symbol = :time)
    sortby  in (:time, :ncalls, :allocations, :name) || throw(ArgumentError("sortby should be :time, :allocations, :ncalls or :name, got $sortby"))
    # For the root node, some computations are slightly different:
    #  - There is no parent, and we report totals for times and allocs
   out_timings = _collect_timings_root(to, sortby)
end

function _collect_timings_root(to::TimerOutput, sortby)
    ∑t, ∑b = to.flattened ? to.totmeasured : totmeasured(to)

    stats = (;
        name = to.name,
        parent = to,  # For root, we use itself as its parent
        ncalls = 0,

        incl_time = ∑t,
        excl_time = 0,
        avg_time  = Float64(∑t),

        incl_allocs = ∑b,
        excl_allocs = 0,
        avg_allocs  = Float64(∑b),
    )
    out_timings = [stats]
    for timer in sort!(collect(values(to.inner_timers)), rev = sortby != :name, by = x -> sortf(x, sortby))
        _collect_timings(timer, to, sortby, out_timings)
    end
    return out_timings
end
function _collect_timings(to::TimerOutput, parent::TimerOutput, sortby, out_timings::Union{Nothing,Vector})
    accum_data = to.accumulated_data
    t = accum_data.time
    b = accum_data.allocs

    nc = accum_data.ncalls

    children_time = sum([0, (child.accumulated_data.time for child in values(to.inner_timers))...])
    children_allocs = sum([0, (child.accumulated_data.time for child in values(to.inner_timers))...])

    exclusive_t = t - children_time
    exclusive_b = b - children_allocs

    stats = (;
        name = to.name,
        parent = parent,
        ncalls = nc,

        incl_time = t,
        excl_time = exclusive_t,
        avg_time  = t / nc,

        incl_allocs = b,
        excl_allocs = exclusive_b,
        avg_allocs  = b / nc,
    )
    push!(out_timings, stats)

    for timer in sort!(collect(values(to.inner_timers)), rev = sortby != :name, by = x -> sortf(x, sortby))
        _collect_timings(timer, to, sortby, out_timings)
    end

    return out_timings
end
