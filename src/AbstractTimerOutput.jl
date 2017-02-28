@compat abstract type AbstractTimerOutput end

start_time(to::AbstractTimerOutput) = to.start_time
start_allocs(to::AbstractTimerOutput) = to.start_allocs

# Sectionname -> length without 1 space padding on both sides
SECTION_LENGTHS = Dict{Symbol, Int}(
:measure => 9,
:perctot => 6,
:percmeas => 8
)

NCALLS_LENGTH = 9
MAX_SECTION_LENGTH = 20

function show(io::IO, to::AbstractTimerOutput)
    global BOX_MODE, ALLOCATIONS_ENABLED
    now_time, now_allocated = time_ns(), gc_bytes()
    dash = BOX_MODE == :unicode ? "─" : "-"
    topbottom = BOX_MODE == :unicode ? "═" : "="
    section_length_sum = sum(v -> v[2], SECTION_LENGTHS)
    tot_row_length = MAX_SECTION_LENGTH + NCALLS_LENGTH + section_length_sum
    if ALLOCATIONS_ENABLED
        tot_row_length += section_length_sum + 3
    end
    tot_timed, tot_allocated = totmeasured(to)
    since_start_time, since_start_alloc = (now_time - start_time(to)), (now_allocated - start_allocs(to))
    hangout(str) = (section_length_sum - strwidth(str)) ÷ 2
    hangout_t = hangout("Time")
    hangout_a = hangout("Allocations")
    str_time = string(prettytime(tot_timed), " / ", prettypercent(tot_timed, since_start_time))
    hangout_tot_time = hangout(str_time)
        
    str_alloc = string(prettymemory(tot_allocated), " / ", prettypercent(tot_allocated, since_start_alloc))
    hangout_tot_alloc = hangout(str_alloc)

    
    print(io, " ", topbottom^tot_row_length, "\n")
    print(io, " ", " "^(2 + MAX_SECTION_LENGTH + NCALLS_LENGTH))
    print(io, " "^hangout_t, "Time", " "^hangout_t)
    ALLOCATIONS_ENABLED && print(io, "  ", " "^hangout_a, "Allocations", " "^hangout_a)
    print(io, "\n")
    print(io, " ", " "^(1 + MAX_SECTION_LENGTH + NCALLS_LENGTH))
    print(io, dash^(section_length_sum -1))
    ALLOCATIONS_ENABLED && print(io, "   ")
    ALLOCATIONS_ENABLED && print(io, dash^(section_length_sum))
    print(io, "\n")
    print(io, "  Total/percentage measured:    ")
    print(io, " "^hangout_tot_time, str_time, " "^hangout_tot_time)
    ALLOCATIONS_ENABLED && print(io, "  ", " "^hangout_tot_alloc, str_alloc, " "^hangout_tot_alloc)

    print(io, "\n")
    print(io, "                                                                \n")
    print(io, "  Section              ncalls    time   %tot  %timed")
    if ALLOCATIONS_ENABLED
        print(io, "      alloc   %tot  %alloc\n")
    else
        print(io, "\n")
    end
    print(io, " ", dash^tot_row_length, "\n")
    print_sections(io, to, since_start_time, tot_timed, since_start_alloc, tot_allocated)
    print(io, " ", topbottom^tot_row_length, "\n")
end

function print_section(io::IO, section::AbstractString, time_data::TimeData, since_start_time, tot_timed, since_start_alloc, tot_allocated)
    global ALLOCATIONS_ENABLED
    total_time = tottime(time_data)
    total_alloc = totallocs(time_data)
    if length(section) >= MAX_SECTION_LENGTH
        section = section[1:MAX_SECTION_LENGTH-3] * "..."
    end
    print(io, "  ")
    nc = ncalls(time_data)
    print(io, rpad(section, MAX_SECTION_LENGTH + 2))
    print(io, " "^(5 - ndigits(nc)), nc)

    print(io, "   ", prettytime(total_time))
    print(io, "  ",  prettypercent(total_time, since_start_time))
    print(io, "  ", prettypercent(total_time, tot_timed))

    if ALLOCATIONS_ENABLED
    print(io, "     ", prettymemory(total_alloc))
    print(io, "  ",  prettypercent(total_alloc, since_start_alloc))
    print(io, "  ", prettypercent(total_alloc, tot_allocated))
    end
    print(io, "\n")
end

