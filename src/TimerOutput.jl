type TimerOutput <: AbstractTimerOutput
    start_time::UInt64
    start_allocs::UInt64
    sections::Dict{String, TimeData}
    start_data::Dict{String, Tuple{UInt64, UInt64}}
    last_section::String
end

sections(to::TimerOutput) = to.sections

function TimerOutput()
    sections = Dict{String, TimeData}()
    start_time, start_allocs = time_ns(), gc_bytes()
    start_data = Dict{String, Tuple{UInt64, UInt64}}()
    return TimerOutput(start_time, start_allocs, sections, start_data, "")
end

function totmeasured(to::TimerOutput)
    t = UInt64(0)
    b = UInt64(0)
    for time_data in values(to.sections)
        t += tottime(time_data)
        b += totallocs(time_data)
    end
    return t, b
end


function reset_timer!(to::TimerOutput)
    to.sections = Dict{String, TimeData}()
    to.start_time = time_ns()
    to.start_allocs = gc_bytes()
    return to
end

function timer_expr(to::Symbol, label::String, ex::Expr)
    quote
        local time_data = get!(sections($(esc(to))), $(esc(label)), TimeData(0, 0, 0))
        local elapsedtime = time_ns()
        local allocedbytes = gc_bytes()
        local val = $(esc(ex))
        elapsedtime = time_ns() - elapsedtime
        allocedbytes = gc_bytes() - allocedbytes
        time_data.tottime += elapsedtime
        time_data.totallocs += allocedbytes
        time_data.ncalls += 1
        val
    end
end

function time_section(f::Function, to::TimerOutput, label)
    if !(typeof(label) <: AbstractString)
        throw(ArgumentError("section did not get evaluated to a string"))
    end
    time_data = get!(sections(to), label, TimeData(0, 0, 0))
    elapsedtime = time_ns()
    allocedbytes = gc_bytes()
    local val
    try
        val = f()
    finally
        elapsedtime = time_ns() - elapsedtime
        allocedbytes = gc_bytes() - allocedbytes
        time_data.tottime += elapsedtime
        time_data.totallocs += allocedbytes
        time_data.ncalls += 1
    end
    return val
end

function enter_section(to::TimerOutput, label::AbstractString)
    to.last_section = label
    to.start_data[label] = time_ns(), gc_bytes()
end


function exit_section(to::TimerOutput, label::AbstractString = to.last_section)
    end_time, end_allocs = time_ns(), gc_bytes()
    start_time, start_allocs = to.start_data[label]
    time_data = get!(sections(to), label, TimeData(0, 0, 0))
    time_data.tottime += end_time - start_time
    time_data.totallocs += end_allocs - start_allocs
    time_data.ncalls += 1
end

function print_sections(io::IO, to::TimerOutput, since_start, tot_timed, since_start_alloc, tot_allocated)
    keys_v = collect(keys(sections(to)))
    values_v = collect(values(sections(to)))
    for i in reverse(sortperm(values_v))
        section = keys_v[i]
        time_data = values_v[i]
        print_section(io, section, time_data, since_start, tot_timed, since_start_alloc, tot_allocated)
    end
end
