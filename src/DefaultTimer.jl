type DefaultTimer <: AbstractTimerOutput
    start_time::UInt64
    start_allocs::UInt64
    time_datas::Vector{TimeData}
    labels::Vector{String}
end

function DefaultTimer()
    time_datas = Vector{TimeData}()
    labels = Vector{String}()
    start_time = time_ns()
    start_allocs = gc_bytes()
    return DefaultTimer(start_time, start_allocs, time_datas, labels)
end

const DEFAULT_TIMER = DefaultTimer()

function totmeasured(dt::DefaultTimer)
    b = UInt64(0)
    t = UInt64(0)
    for time_data in dt.time_datas
        t += tottime(time_data)
        b += totallocs(time_data)
    end
    return t, b
end

function reset_timer!()
    for timedata in DEFAULT_TIMER.time_datas
        reset!(timedata)
    end
    DEFAULT_TIMER.start_time = time_ns()
    DEFAULT_TIMER.start_allocs = gc_bytes()
    return
end

function timer_expr(label::AbstractString, ex::Expr)
    idx = findfirst(DEFAULT_TIMER.labels, label)
    if idx == 0
        push!(DEFAULT_TIMER.labels, label)
        push!(DEFAULT_TIMER.time_datas, TimeData(0, 0, 0))
        idx = length(DEFAULT_TIMER.labels)
    end
    quote
        local time_data = DEFAULT_TIMER.time_datas[$idx]
        local elapsedtime = time_ns()
        local allocedbytes = gc_bytes()
        local val = $(esc(ex))
        allocedbytes = gc_bytes() - allocedbytes
        elapsedtime = time_ns() - elapsedtime
        time_data.tottime += elapsedtime
        time_data.totallocs += allocedbytes
        time_data.ncalls += 1
        val
    end
end


print_timer(io::IO = STDOUT) = print(io, DEFAULT_TIMER)

function print_sections(io::IO, to::DefaultTimer, since_start, tot_timed, since_start_alloc, tot_allocated)
    times = to.time_datas
    labels = to.labels
    for i in reverse(sortperm(times))
        print_section(io, labels[i], times[i], since_start, tot_timed, since_start_alloc, tot_allocated)
    end
end
