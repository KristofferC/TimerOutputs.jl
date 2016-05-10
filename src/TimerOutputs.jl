module TimerOutputs

#using Compat; import Compat.String when Compat is tagged

import Base: show, time_ns
export TimerOutput, @timeit, @timer, reset_timer!, print_timer, time_section, enter_section, exit_section

typealias SectionName UTF8String # String when Compat is tagged

type TimeData
    ncalls::Int
    tottime::UInt64
end

ncalls(td::TimeData) = td.ncalls
tottime(td::TimeData) = td.tottime
Base.isless(self::TimeData, other::TimeData) = self.tottime < other.tottime

function reset!(td::TimeData)
    td.ncalls = 0
    td.tottime = 0
end

abstract AbstractTimerOutput

start(to::AbstractTimerOutput) = to.start_time

function show(io::IO, to::AbstractTimerOutput)
    now = time_ns()
    since_start = now - start(to)
    print(io, "+--------------------------------+-----------+--------+---------+\n")
    print(io, "| Wall time elapsed since start  |")
    print(io, @sprintf("%8.3g s", since_start / 1e9))
    print(io,                                             " |        |         |\n")
    print(io, "|                                |           |        |         |\n")
    print(io, "| Section              | n calls | wall time | % tot  | % timed |\n")
    print(io, "+----------------------+---------+-----------+--------+---------+\n")
    print_sections(io, to, since_start)
    print(io, "+----------------------+---------+-----------+--------+---------+")
end

function print_section(io::IO, section::AbstractString, time_data::TimeData, since_start, tot_timed)
    if length(section) >= 20
        section = section[1:20-3] * "..."
    end

    print(io, @sprintf("| %-20s | %7d | %7.3g s | %5.3g%% | %6.3g%% |\n", section, ncalls(time_data),
                                                               tottime(time_data) / 1e9,
                                                               tottime(time_data) / since_start * 100,
                                                               tottime(time_data) / tot_timed * 100))
end

if !isdefined(Main, :DISABLE_TIMING)
    @eval begin
        macro timeit(args...)
            return timer_expr(args...)
        end
    end
else
    @eval begin
        macro timeit(label::AbstractString, ex::Expr)
            esc(ex)
        end
    end
end

timer_expr(args...) = throw(ErrorException("Invalid macro usage for @timeit"))

include("runtime_timer.jl")

end # module
