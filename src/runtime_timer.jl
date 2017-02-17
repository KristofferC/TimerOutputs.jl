type TimerOutput <: AbstractTimerOutput
    start_time::UInt64
    sections::Dict{SectionName, TimeData}
    start_times::Dict{SectionName, UInt64}
    last_section::SectionName
end

sections(to::TimerOutput) = to.sections

function TimerOutput()
    sections = Dict{SectionName, TimeData}()
    start_time = time_ns()
    start_times = Dict{SectionName, UInt64}()
    return TimerOutput(start_time, sections, start_times, "")
end

function tottimed(to::TimerOutput)
    s = UInt64(0)
    for time_data in values(to.sections)
        s += time_data.tottime
    end
    return s
end


function reset_timer!(to::TimerOutput)
    to.sections = Dict{SectionName, TimeData}()
    to.start_time = time_ns()
    return to
end

function timer_expr(to::Symbol, label, ex::Expr)
    quote
        time_section($(esc(to)), $(esc(label))) do
            $(esc(ex))
        end
    end
end

function time_section(f::Function, to::TimerOutput, label)
    if !(typeof(label) <: AbstractString)
        throw(ArgumentError("section did not get evaluated to a string"))
    end
    time_data = get!(sections(to), label, TimeData(0, 0))
    elapsedtime = time_ns()
    local val
    try
        val = f()
    finally
        elapsedtime = time_ns() - elapsedtime
        time_data.tottime += elapsedtime
        time_data.ncalls += 1
    end
    return val
end

function enter_section(to::TimerOutput, label::AbstractString)
    start_time = time_ns()
    to.last_section = label
    to.start_times[label] = start_time
end


function exit_section(to::TimerOutput, label::AbstractString = to.last_section)
    end_time = time_ns()
    start_time = to.start_times[label]
    time_data = get!(sections(to), label, TimeData(0, 0))
    time_data.tottime += end_time - start_time
    time_data.ncalls += 1
end

function print_sections(io::IO, to::TimerOutput, since_start, tot_timed)
    keys_v = collect(keys(sections(to)))
    values_v = collect(values(sections(to)))
    for i in reverse(sortperm(values_v))
        section = keys_v[i]
        time_data = values_v[i]
        print_section(io, section, time_data, since_start, tot_timed)
    end
end
