print_timer() = show(STDOUT, DEFAULT_TIMER)
print_timer(io::IO) = show(io, DEFAULT_TIMER)
print_timer(io::IO, to::TimerOutput) = show(io, to)
print_timer(to::TimerOutput) = show(STDOUT, to)

function print_header(io, t₀, b₀, ∑t, ∑b, name_length, header, show_alloc)
    global BOX_MODE, ALLOCATIONS_ENABLED

    midrule       = BOX_MODE == :unicode ? "─" : "-"
    topbottomrule = BOX_MODE == :unicode ? "─" : "-"
    sec_ncalls = string(" ", rpad("Section", name_length, " "), " ncalls  ")
    time_headers = "  time   %tot  %timed "
    alloc_headers = show_alloc ? "  alloc   %tot  %alloc " : ""
    total_table_width = sum(strwidth.((sec_ncalls, time_headers, alloc_headers))) + 3
    if !show_alloc
        total_table_width -= 3
    end

    function center(str, len)
        x = (len - strwidth(str)) ÷ 2
        return string(" "^x, str, " "^(len - strwidth(str) - x))
    end

    if header
        time_alloc_pading = " "^(strwidth(sec_ncalls))

        time_header       = "         Time         "
        time_underline = midrule^strwidth(time_header)

        allocation_header = "      Allocations      "
        alloc_underline = midrule^strwidth(allocation_header)

        tot_meas_str = string(" ", rpad("Tot / % measured:", strwidth(sec_ncalls) - 1, " "))

        str_time =  center(string(prettytime(∑t)    , " / ", prettypercent(∑t, t₀)), strwidth(time_header))
        str_alloc = center(string(prettymemory(∑b)  , " / ", prettypercent(∑b, b₀)), strwidth(allocation_header))

        header_str = string(" time   %tot  %timed")
        tot_midstr = string(sec_ncalls, "  ", header_str)
        print(io, " ", Crayon(bold = true)(topbottomrule^total_table_width), "\n")
        print(io, " ", time_alloc_pading, time_header)
        show_alloc && print(io, "   ", allocation_header)
        print(io, "\n")
        print(io, " ", time_alloc_pading, time_underline)
        show_alloc && print(io, "   ", alloc_underline)
        print(io, "\n")
        print(io, " ", tot_meas_str, str_time)
        show_alloc && print(io, "   ", str_alloc)
        print(io, "\n\n")
        print(io, " ", sec_ncalls, time_headers)
        show_alloc && print(io, "   ", alloc_headers)
        print(io, "\n")
        print(io, " ", midrule^total_table_width, "\n")
    else
        print(io, " ", Crayon(bold = true)(topbottomrule^total_table_width))
    end
end

function Base.show(io::IO, to::TimerOutput)
    max_name = longest_name(to)
    available_width = displaysize(io)[2]
    show_alloc = ALLOCATIONS_ENABLED
    requested_width = 34 + (show_alloc ? 27 : 0) + max_name
    name_length = max(9, max_name - max(0, requested_width - available_width))

    t₀, b₀ = time_ns(), gc_bytes()
    t₁, b₁ = to.start_data.time, to.start_data.allocs
    Δt, Δb = t₁ - t₀, b₁ - b₀
    ∑t, ∑b = totmeasured(to)

    print_header(io, t₀, b₀, ∑t, ∑b, name_length, true, show_alloc)
    for timer in sort!(collect(values(to.inner_timers)), rev = true)
        _print_timer(io, timer, ∑t, ∑b, 0, name_length, show_alloc)
    end
    print_header(io, t₀, b₀, ∑t, ∑b, name_length, false, show_alloc)
end

function _print_timer(io::IO, to::TimerOutput, ∑t::Integer, ∑b::Integer, indent::Integer, name_length, show_alloc)
    accum_data = to.accumulated_data
    t = accum_data.time
    b = accum_data.allocs
    name = to.name
    if length(name) >= name_length - indent
        name = string(name[1:name_length-3-indent], "...")
    end
    print(io, "  ")
    nc = accum_data.ncalls
    print(io, " "^indent, rpad(name, name_length + 2-indent))
    print(io, " "^(5 - ndigits(nc)), nc)

    print(io, "   ", lpad(prettytime(t),        6, " "))
    print(io, "  ",  lpad(prettypercent(t, ∑t), 5, " "))
    print(io, "  ",  lpad(prettypercent(t, ∑t), 5, " "))

    if show_alloc
    print(io, "     ", lpad(prettymemory(b),      7, " "))
    print(io, "  ",    lpad(prettypercent(b, ∑b), 5, " "))
    print(io, "  ",    lpad(prettypercent(b, ∑b), 5, " "))
    end
    print(io, "\n")
    for timer in sort!(collect(values(to.inner_timers)), rev = true)
        _print_timer(io, timer, ∑t, ∑b, indent + 2, name_length, show_alloc)
    end
end
