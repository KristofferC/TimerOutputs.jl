print_timer(; kwargs...) = print_timer(stdout; kwargs...)
print_timer(to::TimerOutput; kwargs...) = print_timer(stdout, to; kwargs...)
print_timer(io::IO; kwargs...) = print_timer(io, DEFAULT_TIMER; kwargs...)
print_timer(io::IO, to::TimerOutput; kwargs...) = (show(io, to; kwargs...); println(io))

Base.show(to::TimerOutput; kwargs...) = show(stdout, to; kwargs...)
function Base.show(io::IO, to::TimerOutput; allocations::Bool = true, sortby::Symbol = :time, linechars::Symbol = :unicode, compact::Bool = false, title::String = "")
    sortby  in (:time, :ncalls, :allocations, :name, :firstexec) || throw(ArgumentError("sortby should be :time, :allocations, :ncalls, :name, or :firstexec, got $sortby"))
    linechars in (:unicode, :ascii)                  || throw(ArgumentError("linechars should be :unicode or :ascii, got $linechars"))

    t₀, b₀ = to.start_data.time, to.start_data.allocs
    t₁, b₁ = time_ns(), gc_bytes()
    Δt, Δb = t₁ - t₀, b₁ - b₀
    ∑t, ∑b = to.flattened ? to.totmeasured : totmeasured(to)

    max_name = longest_name(to)
    available_width = displaysize(io)[2]
    requested_width = max_name
    if compact
        if allocations
            requested_width += 43
        else
            requested_width += 25
        end
    else
        if allocations
            requested_width += 59
        else
            requested_width += 33
        end
    end


    #requested_width = 34 + (allocations ? 27 : 0) + max_name
    name_length = max(9, max_name - max(0, requested_width - available_width))

    print_header(io, Δt, Δb, ∑t, ∑b, name_length, true, allocations, linechars, compact, title)
    rev = !in(sortby, [:name, :firstexec])
    by(x) = sortf(x, sortby)
    for timer in sort!(collect(values(to.inner_timers)); rev = rev, by = by)
        _print_timer(io, timer, ∑t, ∑b, 0, name_length, allocations, sortby, compact)
    end
    print_header(io, Δt, Δb, ∑t, ∑b, name_length, false, allocations, linechars, compact, title)
end

function sortf(x, sortby)
    sortby == :time        && return x.accumulated_data.time
    sortby == :ncalls      && return x.accumulated_data.ncalls
    sortby == :allocations && return x.accumulated_data.allocs
    sortby == :name        && return x.name
    sortby == :firstexec   && return x.accumulated_data.firstexec
    error("internal error")
end

# truncate string and add dots
function truncdots(str, n)
    textwidth(str) <= n && return str
    n <= 3 && return ""
    io = IOBuffer()
    for (i, c) in enumerate(str)
        i == n - 2 && (write(io, "..."); break)
        write(io, c)
    end
    return String(take!(io))
end

function print_header(io, Δt, Δb, ∑t, ∑b, name_length, header, allocations, linechars, compact, title)
    global BOX_MODE, ALLOCATIONS_ENABLED

    midrule       = linechars == :unicode ? "─" : "-"
    topbottomrule = linechars == :unicode ? "─" : "-"
    sec_ncalls = string(rpad("Section", name_length, " "), " ncalls  ")
    time_headers = "   time    %tot" * (compact ? "" : "     avg")
    alloc_headers = allocations ? ("  alloc    %tot" * (compact ? "" : "      avg")) : ""
    total_table_width = sum(textwidth.((sec_ncalls, time_headers, alloc_headers))) + 3

    # Just hardcoded shit to make things look nice
    !allocations && (total_table_width -= 3)

    function center(str, len)
        x = (len - textwidth(str)) ÷ 2
        return string(" "^x, str, " "^(len - textwidth(str) - x))
    end

    if header
        time_alloc_pading = " "^(textwidth(sec_ncalls))

        title = center(truncdots(title, textwidth(sec_ncalls)), textwidth(sec_ncalls))

        if compact
            time_header       = "      Time     "
        else
            time_header       = "         Time          "
        end

        time_underline = midrule^textwidth(time_header)

        if compact
            allocation_header       = "  Allocations  "
        else
            allocation_header = "       Allocations      "
        end

        alloc_underline = midrule^textwidth(allocation_header)
        #tot_meas_str = string(" ", rpad("Tot / % measured:", textwidth(sec_ncalls) - 1, " "))
        if compact
            tot_meas_str = center("Total measured:", textwidth(sec_ncalls))
        else
            tot_meas_str = center("Tot / % measured:", textwidth(sec_ncalls))
        end

        str_time =  center(string(prettytime(Δt),   compact ? "" : string(" / ", prettypercent(∑t, Δt))), textwidth(time_header))
        str_alloc = center(string(prettymemory(Δb), compact ? "" : string(" / ", prettypercent(∑b, Δb))), textwidth(allocation_header))

        header_str = string("  time  %tot  %timed")
        tot_midstr = string(sec_ncalls, "  ", header_str)
        printstyled(io, " ", topbottomrule^total_table_width, "\n"; bold=true)
        if ! (allocations == false && compact == true)
            printstyled(io, " ", title; bold=true)
            print(io, time_header)
            allocations && print(io, "   ", allocation_header)
            print(io, "\n")
            print(io, " ", time_alloc_pading, time_underline)
            allocations && print(io, "   ", alloc_underline)
            print(io, "\n")
            print(io, " ", tot_meas_str, str_time)
            allocations && print(io, "   ", str_alloc)
            print(io, "\n\n")
        end
        print(io, " ", sec_ncalls, time_headers)
        allocations && print(io, "   ", alloc_headers)
        print(io, "\n")
        print(io, " ", midrule^total_table_width, "\n")
    else
        printstyled(io, " ", topbottomrule^total_table_width; bold=true)
    end
end

function _print_timer(io::IO, to::TimerOutput, ∑t::Integer, ∑b::Integer, indent::Integer, name_length, allocations, sortby, compact)
    accum_data = to.accumulated_data
    t = accum_data.time
    b = accum_data.allocs

    name = truncdots(to.name, name_length - indent)
    print(io, " ")
    nc = accum_data.ncalls
    print(io, " "^indent, rpad(name, name_length + 2 - indent))
    print(io, lpad(prettycount(nc), 5, " "))

    print(io, "   ", lpad(prettytime(t),        6, " "))
    print(io, "  ",  lpad(prettypercent(t, ∑t), 5, " "))
    !compact && print(io, "  ",  rpad(prettytime(t / nc), 6, " "))

    if allocations
    print(io, "   ", rpad(prettymemory(b),      9, " "))
    print(io, rpad(prettypercent(b, ∑b), 5, " "))
    !compact && print(io, "  ",    lpad(prettymemory(b / nc), 5, " "))
    end
    print(io, "\n")

    rev = !in(sortby, [:name, :firstexec])
    by(x) = sortf(x, sortby)
    for timer in sort!(collect(values(to.inner_timers)); rev = rev, by = by)
        _print_timer(io, timer, ∑t, ∑b, indent + 2, name_length, allocations, sortby, compact)
    end
end
