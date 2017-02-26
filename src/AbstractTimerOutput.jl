@compat abstract type AbstractTimerOutput end

start(to::AbstractTimerOutput) = to.start_time

function show(io::IO, to::AbstractTimerOutput)
    now = time_ns()
    since_start = now - start(to)
    tot_timed = sum(tottimed(to))
    print(io, "+--------------------------------+-----------+--------+---------+\n")
    print(io, "| Wall time elapsed since start  |")
    print(io, @sprintf("%8.3g s", since_start / 1e9))
    print(io,                                             " |        |         |\n")
    print(io, "|                                |           |        |         |\n")
    print(io, "| Section              | n calls | wall time | % tot  | % timed |\n")
    print(io, "+----------------------+---------+-----------+--------+---------+\n")
    print_sections(io, to, since_start, tot_timed)
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