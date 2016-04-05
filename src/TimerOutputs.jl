module TimerOutputs

include("utility.jl")

import Base: show, time_ns

export TimerOutput, @timeit, reset!

typealias SectionName UTF8String

type TimeData
    ncalls::Int
    tottime::UInt64
end
ncalls(td::TimeData) = td.ncalls
tottime(td::TimeData) = td.tottime

Base.isless(self::TimeData, other::TimeData) = self.tottime < other.tottime


type TimerOutput
    start_time::UInt64
    sections::Dict{SectionName, TimeData}
end

sections(to::TimerOutput) = to.sections
start(to::TimerOutput) = to.start_time

function TimerOutput()
    sections = Dict{SectionName, TimeData}()
    start_time = time_ns()
    return TimerOutput(start_time, sections)
end

function reset!(to::TimerOutput)
    to.sections = Dict{SectionName, TimeData}()
    to.start_time = time_ns()
    return to
end

if !isdefined(Main, :DISABLE_TIMING)
    @eval begin
        macro timeit(to::Symbol, label::AbstractString, ex::Expr)
            quote
               local time_data = get!(sections($(esc(to))), $(esc(label)), TimeData(0, 0))
               local elapsedtime = time_ns()
               local val = $(esc(ex))
               elapsedtime = time_ns() - elapsedtime
               time_data.tottime += elapsedtime
               time_data.ncalls += 1
               val
            end
        end
    end
else
    @eval begin
        macro timeit(to::Symbol, label::AbstractString, ex::Expr)
            return esc(ex)
        end
    end
end

function show(io::IO, to::TimerOutput)
    now = time_ns()
    since_start = now - start(to)
    print(io, "+---------------------------------------------+------------+------------+\n")
    print(io, "| Total wallclock time elapsed since start    |")
    print(io, time_print(since_start))
    print(io,                                                           " |            |\n")
    print(io, "|                                             |            |            |\n")
    print(io, "| Section                         | no. calls |  wall time | % of total |\n")
    print(io, "+---------------------------------------------+------------+------------+\n")
    keys_v = collect(keys(sections(to)))
    values_v = collect(values(sections(to)))
    for i in reverse(sortperm(values_v))
        section = keys_v[i]
        time_data = values_v[i]
        if length(section) >= 31
            section = section[1:31-3] * "..."
        end
        print(io, @sprintf("| %-31s | %9d |", section, ncalls(time_data)))
        print(io, time_print(tottime(time_data)))
        print(io, @sprintf(" | %8.2g %% |\n", tottime(time_data) / since_start * 100))
    end
    print(io, "+---------------------------------------------+------------+------------+\n")
end

# Compile so the first run looks ok
to = TimerOutput()
@timeit to "blah" sleep(0.000001)

end # module
