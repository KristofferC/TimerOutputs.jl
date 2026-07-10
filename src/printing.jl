#####################
# Value formatting  #
#####################

function prettytime(t)
    # can be NaN for the avg column if a section never finished (ncalls == 0)
    isnan(t) && return lpad("-", 6, " ")
    if t < 1.0e3
        value, units = t, "ns"
    elseif t < 1.0e6
        value, units = t / 1.0e3, "μs"
    elseif t < 1.0e9
        value, units = t / 1.0e6, "ms"
    elseif t < 3600.0e9
        value, units = t / 1.0e9, "s"
        # We intentionally do not show minutes
    else
        value, units = t / 3600.0e9, "h"
    end

    if round(value) >= 100
        str = string(@sprintf("%.0f", value), units)
    elseif round(value * 10) >= 100
        str = string(@sprintf("%.1f", value), units)
    else
        str = string(@sprintf("%.2f", value), units)
    end
    return lpad(str, 6, " ")
end

function prettymemory(b)
    if b < 1000
        value, units = b, "B"
    elseif b < 1000^2
        value, units = b / 1024, "KiB"
    elseif b < 1000^3
        value, units = b / 1024^2, "MiB"
    elseif b < 1000^4
        value, units = b / 1024^3, "GiB"
    elseif b < 1000^5
        value, units = b / 1024^4, "TiB"
    elseif b < 1000^6
        value, units = b / 1024^5, "PiB"
    else
        value, units = b / 1024^6, "EiB"
    end

    if round(value) >= 100
        str = string(@sprintf("%.0f", value), units)
    elseif round(value * 10) >= 100
        str = string(@sprintf("%.1f", value), units)
    elseif value >= 0
        str = string(@sprintf("%.2f", value), units)
    else
        str = "-"
    end
    return lpad(str, 7, " ")
end

function prettypercent(numerator, denominator)
    value = numerator / denominator * 100
    if denominator == 0 && numerator == 0
        str = " - %"
    elseif denominator == 0
        str = "inf %"
    else
        str = string(@sprintf("%.1f", value), "%")
    end
    return lpad(str, 6, " ")
end

function prettycount(t::Integer)
    if t < 1000
        return string(t)
    elseif t < 1000^2
        value, units = t / 1000, "k"
    elseif t < 1000^3
        value, units = t / 1.0e6, "M"
    else
        value, units = t / 1.0e9, "B"
    end

    if round(value) >= 100
        str = string(@sprintf("%.0f", value), units)
    elseif round(value * 10) >= 100
        str = string(@sprintf("%.1f", value), units)
    else
        str = string(@sprintf("%.2f", value), units)
    end
    return str
end

##################
# Table building #
##################

const SORTBY_OPTIONS = (:time, :ncalls, :allocations, :name, :firstexec)

function sortf(s::Section, sortby::Symbol)
    sortby === :time && return s.time
    sortby === :ncalls && return s.ncalls
    sortby === :allocations && return s.allocs
    sortby === :firstexec && return s.firstexec
    return error("internal error")
end

# non-mutating: the live children vector must not be reordered
function sorted_children(s::Section, sortby::Symbol)
    if sortby === :name
        return sort(s.children; by = c -> c.name)
    else
        return sort(s.children; rev = sortby !== :firstexec, by = c -> sortf(c, sortby))
    end
end

# tree guide pieces: (branch, last branch, continuation, blank)
tree_guides(linechars::Symbol) =
    linechars === :unicode ? ("├─ ", "└─ ", "│  ", "   ") : ("+- ", "`- ", "|  ", "   ")

# with linechars = :ascii the output should be pure ASCII, including in the
# time unit (#115)
asciitime(str, ascii::Bool) = ascii ? replace(str, "μs" => "us") : str

# integer percentage of the enclosing section; blank at the top level (#192)
prettypar(v, parent) = parent <= 0 ? "" : string(round(Int, v / parent * 100), "%")

struct TableOptions
    sortby::Symbol
    allocations::Bool
    compact::Bool
    ascii::Bool
    maxdepth::Int
    guides::NTuple{4, String}
end

# Top level sections print flush; nested ones get tree guides.
function table_rows!(
        rows::Vector{Vector{String}}, s::Section, ∑t, ∑b,
        prefix::String, depth::Int, parent_t, parent_b, opts::TableOptions
    )
    depth > opts.maxdepth && return rows
    toplevel = depth == 1
    children = sorted_children(s, opts.sortby)
    for (i, child) in enumerate(children)
        islast = i == length(children)
        name = toplevel ? child.name : string(prefix, islast ? opts.guides[2] : opts.guides[1], child.name)
        row = String[
            name, prettycount(child.ncalls),
            asciitime(prettytime(child.time), opts.ascii), prettypercent(child.time, ∑t),
        ]
        if !opts.compact
            push!(row, prettypar(child.time, toplevel ? 0 : parent_t))
            push!(row, asciitime(prettytime(child.time / child.ncalls), opts.ascii))
        end
        if opts.allocations
            push!(row, prettymemory(child.allocs))
            push!(row, prettypercent(child.allocs, ∑b))
            if !opts.compact
                push!(row, prettypar(child.allocs, toplevel ? 0 : parent_b))
                push!(row, prettymemory(child.allocs / child.ncalls))
            end
        end
        push!(rows, row)
        child_prefix = toplevel ? "" : string(prefix, islast ? opts.guides[4] : opts.guides[3])
        table_rows!(rows, child, ∑t, ∑b, child_prefix, depth + 1, child.time, child.allocs, opts)
    end
    return rows
end

############
# Printing #
############

print_timer(; kwargs...) = print_timer(stdout; kwargs...)
print_timer(to::Union{TimerOutput, ConcurrentTimerOutput}; kwargs...) = print_timer(stdout, to; kwargs...)
print_timer(io::IO; kwargs...) = print_timer(io, DEFAULT_TIMER; kwargs...)
print_timer(io::IO, to::TimerOutput; kwargs...) = (show_table(io, to; kwargs...); println(io))
print_timer(io::IO, cto::ConcurrentTimerOutput; kwargs...) = print_timer(io, merged(cto); kwargs...)

Base.show(to::TimerOutput; kwargs...) = show(stdout, to; kwargs...)
Base.show(cto::ConcurrentTimerOutput; kwargs...) = show(stdout, cto; kwargs...)

function Base.show(io::IO, cto::ConcurrentTimerOutput; kwargs...)
    if in_container(io) && isempty(kwargs)
        n = length(merged(cto).root.children)
        return print(io, "ConcurrentTimerOutput(", n, n == 1 ? " section)" : " sections)")
    end
    return show_table(io, merged(cto); kwargs...)
end

# Inside containers print a one line summary instead of the full table.
# Container printing marks its context with :typeinfo (and matrix display
# additionally with :compact).
in_container(io::IO) = get(io, :compact, false)::Bool || haskey(io, :typeinfo)

function Base.show(io::IO, to::TimerOutput; kwargs...)
    if in_container(io) && isempty(kwargs)
        n = length(to.root.children)
        return print(io, "TimerOutput(", repr(to.root.name), ", ", n, n == 1 ? " section)" : " sections)")
    end
    return show_table(io, to; kwargs...)
end

function Base.show(io::IO, s::Section; kwargs...)
    if in_container(io) && isempty(kwargs)
        return print(
            io, "Section(", repr(s.name), ", ncalls = ", s.ncalls,
            ", time = ", strip(prettytime(s.time)), ")"
        )
    end
    return show_table(io, s; kwargs...)
end

function validated_options(; sortby, allocations, compact, linechars, maxdepth)
    sortby in SORTBY_OPTIONS ||
        throw(ArgumentError("sortby should be :time, :allocations, :ncalls, :name, or :firstexec, got $sortby"))
    linechars in (:unicode, :ascii) ||
        throw(ArgumentError("linechars should be :unicode or :ascii, got $linechars"))
    maxdepth >= 1 ||
        throw(ArgumentError("maxdepth should be at least 1, got $maxdepth"))
    return TableOptions(
        sortby, allocations, compact, linechars === :ascii, maxdepth, tree_guides(linechars)
    )
end

function show_table(
        io::IO, to::TimerOutput;
        sortby::Symbol = :time, allocations::Bool = true, compact::Bool = false,
        linechars::Symbol = :unicode, maxdepth::Int = typemax(Int), title::String = ""
    )
    opts = validated_options(; sortby, allocations, compact, linechars, maxdepth)

    Δt = time_ns() - to.start_time
    Δb = gc_bytes() - to.start_allocs
    ∑t, ∑b = totmeasured(to)

    subtitle = string(
        "Total / % measured: ", strip(asciitime(prettytime(Δt), opts.ascii)),
        " / ", strip(prettypercent(∑t, Δt)),
        allocations ? string("   ", strip(prettymemory(Δb)), " / ", strip(prettypercent(∑b, Δb))) : ""
    )
    return _show_table(io, to.root, ∑t, ∑b, opts, title, subtitle)
end

# A bare section prints as a table too, but has no meaningful wall-clock
# reference, so no "% measured" subtitle.
function show_table(
        io::IO, s::Section;
        sortby::Symbol = :time, allocations::Bool = true, compact::Bool = false,
        linechars::Symbol = :unicode, maxdepth::Int = typemax(Int), title::String = ""
    )
    opts = validated_options(; sortby, allocations, compact, linechars, maxdepth)
    ∑t, ∑b = s.ncalls > 0 ? (s.time, s.allocs) : totmeasured(s)
    return _show_table(io, s, ∑t, ∑b, opts, title, "")
end

function _show_table(io::IO, s::Section, ∑t, ∑b, opts::TableOptions, title, subtitle)
    allocations, compact = opts.allocations, opts.compact
    rows = Vector{Vector{String}}()
    table_rows!(rows, s, ∑t, ∑b, "", 1, 0, 0, opts)

    labels = String["Section", "ncalls", "time", "%tot"]
    compact || append!(labels, ["%par", "avg"])
    if allocations
        append!(labels, ["alloc", "%tot"])
        compact || append!(labels, ["%par", "avg"])
    end
    ncols = length(labels)
    time_cols = compact ? 2 : 4
    group_row = Any[EmptyCells(2), MultiColumn(time_cols, "Time")]
    allocations && push!(group_row, MultiColumn(time_cols, "Allocations"))

    data = if isempty(rows)
        Matrix{String}(undef, 0, ncols)
    else
        permutedims(reduce(hcat, rows))
    end

    pretty_table(
        io, data;
        column_labels = [group_row, labels],
        alignment = [:l; fill(:r, ncols - 1)],
        table_format = if opts.ascii
            TextTableFormat(; borders = text_table_borders__compact, @text__no_vertical_lines)
        else
            TextTableFormat(; @text__no_vertical_lines)
        end,
        style = TextTableStyle(;
            title = crayon"bold",
            subtitle = crayon"dark_gray",
            first_line_merged_column_label = crayon"bold",
            column_label = crayon"default"
        ),
        # crop to the display width in the REPL and on terminals so long
        # section names never make lines wrap (#166)
        fit_table_in_display_horizontally = get(io, :limit, io isa Base.TTY)::Bool,
        title = title,
        title_alignment = :c,
        subtitle = subtitle,
        subtitle_alignment = :c
    )
    return nothing
end
