type DefaultTimer <: AbstractTimerOutput
    start_time::UInt64
    timedatas::Vector{TimeData}
    labels::Vector{UTF8String}
end

function DefaultTimer()
    timedatas = Vector{TimeData}()
    labels = Vector{UTF8String}()
    start_time = time_ns()
    return DefaultTimer(start_time, timedatas, labels)
end

const DEFAULT_TIMER = DefaultTimer()

function tottimed(dt::DefaultTimer)
    s = UInt64(0)
    for td in dt.timedatas
        s += tottime(td)
    end
    return s
end

function reset_timer!()
    DEFAULT_TIMER.start_time = time_ns()
    for timedata in DEFAULT_TIMER.timedatas
        reset!(timedata)
    end
    return
end

function timer_expr(label::AbstractString, ex::Expr)
    idx = findfirst(DEFAULT_TIMER.labels, label)
    if idx == 0
        push!(DEFAULT_TIMER.labels, label)
        push!(DEFAULT_TIMER.timedatas, TimeData(0, 0))
        idx = length(DEFAULT_TIMER.labels)
    end
    quote
       local time_data = DEFAULT_TIMER.timedatas[$idx]
       local elapsedtime = time_ns()
       local val = $(esc(ex))
       elapsedtime = time_ns() - elapsedtime
       time_data.tottime += elapsedtime
       time_data.ncalls += 1
       val
    end
end

print_timer(io::IO=STDOUT) = print(io, DEFAULT_TIMER)

function print_sections(io::IO, to::DefaultTimer, since_start, tot_timed)
    times = to.timedatas
    labels = to.labels
    for i in reverse(sortperm(times))
        print_section(io, labels[i], times[i], since_start, tot_timed)
    end
end