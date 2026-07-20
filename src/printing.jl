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

########
# Heat #
########

# Heat color for a section's share of the total: cold sections fade toward
# blue, hot ones ramp through orange to red, and the middle band keeps the
# terminal's default color. The sqrt spreads out the small percentages most
# sections live at, so they don't all collapse into the blue end.
const COLD_STOPS = ((59, 76, 192), (110, 130, 180))
const HOT_STOPS = ((200, 120, 90), (210, 60, 60), (200, 10, 30))
const COLD_MAX = 0.35 # in sqrt space: below ~12% of the total is "cold"
const HOT_MIN = 0.6  # in sqrt space: above ~36% of the total is "hot"

# piecewise-linear interpolation through the color stops, t in [0, 1]
function lerp_stops(stops, t)
    x = t * (length(stops) - 1)
    i = clamp(floor(Int, x) + 1, 1, length(stops) - 1)
    s = x - (i - 1)
    a, b = stops[i], stops[i + 1]
    return ntuple(k -> round(Int, a[k] + (b[k] - a[k]) * s), 3)
end

function heat_crayon(frac)
    t = sqrt(clamp(frac, 0.0, 1.0))
    t < COLD_MAX && return Crayon(foreground = lerp_stops(COLD_STOPS, t / COLD_MAX))
    t > HOT_MIN && return Crayon(foreground = lerp_stops(HOT_STOPS, (t - HOT_MIN) / (1 - HOT_MIN)))
    return Crayon()
end

# A fixed-width bar filled proportionally to `frac`, quasi-continuous through
# eighth blocks, with the remainder left empty; the heat highlighter colors it
const BAR_EIGHTHS = ("▏", "▎", "▍", "▌", "▋", "▊", "▉")

function heatbar(frac, ascii::Bool; width::Int = 8)
    frac = clamp(frac, 0.0, 1.0)
    ascii && return rpad(repeat('#', round(Int, frac * width)), width, '.')
    full, part = divrem(round(Int, frac * width * 8), 8)
    bar = repeat('█', full) * (part == 0 ? "" : BAR_EIGHTHS[part])
    return rpad(bar, width)
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
function sort_sections!(sections::Vector{Section}, sortby::Symbol)
    if sortby === :name
        return sort!(sections; by = c -> c.name)
    else
        return sort!(sections; rev = sortby !== :firstexec, by = c -> sortf(c, sortby))
    end
end

# tree guide pieces: (branch, last branch, continuation, blank);
# ascii mode uses plain indentation like TimerOutputs 0.5 did
tree_guides(linechars::Symbol) =
    linechars === :unicode ? ("├─ ", "└─ ", "│  ", "   ") : ("  ", "  ", "  ", "  ")

# with linechars = :ascii the output should be pure ASCII, including in the
# time unit (#115)
asciitime(str, ascii::Bool) = ascii ? replace(str, "μs" => "us") : str

# integer percentage of the enclosing section; blank at the top level (#192)
prettypar(v, parent) = parent <= 0 ? "" : string(round(Int, v / parent * 100), "%")

# GC time: sections that never triggered a collection show a null glyph rather
# than a noisy column of "0.00ns" (a plain "-" in pure-ASCII mode, #115)
prettygc(t, ascii::Bool) = t == 0 ? lpad(ascii ? "-" : "∅", 6) : asciitime(prettytime(t), ascii)

###########
# Columns #
###########

# Everything a cell renderer may need besides the section and its parent
struct CellContext
    ∑t::Int64
    ∑b::Int64
    toplevel::Bool
    ascii::Bool
end

# A table column: its header, the merged group header it sits under ("" for
# none), whether it is blanked on summary rows like ~untimed~, and how to
# render a cell. Adding a new column to the table means adding an entry to
# `COLUMNS` below.
struct ColumnSpec
    label::String
    group::String
    blankable::Bool
    cell::Function # (section, parent, ctx::CellContext) -> String
end

const COLUMNS = (;
    spacer = ColumnSpec("", "", false, (c, p, ctx) -> ""),
    ncalls = ColumnSpec("ncalls", "", true, (c, p, ctx) -> prettycount(c.ncalls)),
    time = ColumnSpec("time", "Time", false, (c, p, ctx) -> asciitime(prettytime(c.time), ctx.ascii)),
    time_pct = ColumnSpec("%tot", "Time", true, (c, p, ctx) -> prettypercent(c.time, ctx.∑t)),
    gc_time = ColumnSpec("GC", "Time", true, (c, p, ctx) -> prettygc(c.gc_time, ctx.ascii)),
    time_par = ColumnSpec("%par", "Time", true, (c, p, ctx) -> ctx.toplevel ? "" : prettypar(c.time, p.time)),
    time_avg = ColumnSpec("avg", "Time", true, (c, p, ctx) -> asciitime(prettytime(c.time / c.ncalls), ctx.ascii)),
    allocs = ColumnSpec("alloc", "Allocations", false, (c, p, ctx) -> prettymemory(c.allocs)),
    allocs_pct = ColumnSpec("%tot", "Allocations", true, (c, p, ctx) -> prettypercent(c.allocs, ctx.∑b)),
    allocs_par = ColumnSpec("%par", "Allocations", true, (c, p, ctx) -> ctx.toplevel ? "" : prettypar(c.allocs, p.allocs)),
    allocs_avg = ColumnSpec("avg", "Allocations", true, (c, p, ctx) -> prettymemory(c.allocs / c.ncalls)),
    time_bar = ColumnSpec("", "Time", true, (c, p, ctx) -> heatbar(ctx.∑t > 0 ? c.time / ctx.∑t : 0.0, ctx.ascii)),
    allocs_bar = ColumnSpec("", "Allocations", true, (c, p, ctx) -> heatbar(ctx.∑b > 0 ? c.allocs / ctx.∑b : 0.0, ctx.ascii)),
)

# the selection the `allocations`, `compact`, `bars` and `gc` keywords
# correspond to; the %par columns are opt-in through the `columns` keyword
function default_columns(allocations::Bool, compact::Bool, bars::Bool, gc::Bool)
    columns = [:ncalls, :time, :time_pct]
    gc && push!(columns, :gc_time)
    compact || push!(columns, :time_avg)
    compact || !bars || push!(columns, :time_bar)
    if allocations
        append!(columns, [:spacer, :allocs, :allocs_pct])
        compact || push!(columns, :allocs_avg)
        compact || !bars || push!(columns, :allocs_bar)
    end
    return columns
end

function resolve_columns(ids)
    return map(collect(ids)) do id
        haskey(COLUMNS, id) ||
            throw(ArgumentError("unknown column $(repr(id)), valid columns are $(join(repr.(keys(COLUMNS)), ", "))"))
        getproperty(COLUMNS, id)
    end
end

struct TableOptions
    sortby::Symbol
    columns::Vector{ColumnSpec}
    ascii::Bool
    maxdepth::Int
    complement::Bool
    header::Bool # show the group header and totals block above the column labels
    guides::NTuple{4, String}
end

# A synthetic row shown with the `complement` display option, in gray. For the
# top level `~untimed~` row the counts and percentages are meaningless and
# left blank.
struct ComplementRow
    section::Section
    full_stats::Bool
end

# An instrumented function stores a module-qualified label (`Main.foo`); show
# just the final component. Only set on plain named functions, so the name is a
# dotted identifier and splitting on the last '.' is safe.
bare_name(name::AbstractString) = String(last(rsplit(name, '.'; limit = 2)))

# `@timeit_all` sections carry their source file. A statement row (label
# `file:line: code`) whose file the parent row already carries shortens to
# `L<line>: code`; a function or labeled block row instead shows the file once,
# as `name @ file`, when the parent does not carry it.
function short_label(c::Section, parent_srcfile::Union{String, Nothing})
    c.qualified && return bare_name(c.name)
    f = c.srcfile
    f === nothing && return c.name
    # a complement row wraps its section's label in `~ ~`; shorten the inside
    name = c.is_complement ? chop(c.name; head = 1, tail = 1) : c.name
    prefix = string(f, ':')
    if startswith(name, prefix) # a statement label embedding the file
        f == parent_srcfile || return c.name
        short = string("L", chopprefix(name, prefix))
        return c.is_complement ? string('~', short, '~') : short
    end
    f == parent_srcfile && return c.name # an ancestor row already shows the file
    c.is_complement && return c.name
    return string(c.name, " @ ", f)
end

# Display label for each sibling: shortened as above, unless two siblings would
# collapse to the same string, in which case keep the full names.
function section_labels(children::Vector{Section}, parent_srcfile::Union{String, Nothing})
    shorts = [short_label(c, parent_srcfile) for c in children]
    counts = Dict{String, Int}()
    for short in shorts
        counts[short] = get(counts, short, 0) + 1
    end
    return [counts[shorts[i]] == 1 ? shorts[i] : children[i].name for i in eachindex(children)]
end

# Top level sections print flush; nested ones get tree guides. `gray` collects
# the indices of complement rows for the highlighter. `extra` is a synthetic
# complement row to show among the children of `s`.
function table_rows!(
        rows::Vector{Vector{String}}, gray::Vector{Int}, heats::Vector{NTuple{2, Float64}},
        s::Section, ∑t, ∑b,
        prefix::String, depth::Int, opts::TableOptions, extra::Union{ComplementRow, Nothing}
    )
    depth > opts.maxdepth && return rows
    toplevel = depth == 1
    ctx = CellContext(∑t, ∑b, toplevel, opts.ascii)
    children = copy(s.children)
    extra === nothing || push!(children, extra.section)
    sort_sections!(children, opts.sortby)
    labels = section_labels(children, s.srcfile)
    for (i, child) in enumerate(children)
        islast = i == length(children)
        synthetic = extra !== nothing && child === extra.section
        blank = synthetic && !extra.full_stats
        label = labels[i]
        name = toplevel ? label : string(prefix, islast ? opts.guides[2] : opts.guides[1], label)
        row = Vector{String}(undef, 1 + length(opts.columns))
        row[1] = name
        for (k, column) in enumerate(opts.columns)
            row[k + 1] = blank && column.blankable ? "" : column.cell(child, s, ctx)
        end
        push!(rows, row)
        push!(heats, (∑t > 0 ? child.time / ∑t : 0.0, ∑b > 0 ? child.allocs / ∑b : 0.0))
        synthetic && push!(gray, length(rows))
        child_extra = if opts.complement && !synthetic && !isempty(child.children)
            ComplementRow(complement_section(child), true)
        else
            nothing
        end
        child_prefix = toplevel ? "" : string(prefix, islast ? opts.guides[4] : opts.guides[3])
        table_rows!(rows, gray, heats, child, ∑t, ∑b, child_prefix, depth + 1, opts, child_extra)
    end
    return rows
end

############
# Printing #
############

print_timer(; kwargs...) = print_timer(stdout; kwargs...)
print_timer(to::TimerOutput; kwargs...) = print_timer(stdout, to; kwargs...)
print_timer(io::IO; kwargs...) = print_timer(io, DEFAULT_TIMER; kwargs...)
print_timer(io::IO, to::TimerOutput; kwargs...) = (show_table(io, to; kwargs...); println(io))

Base.show(to::TimerOutput; kwargs...) = show(stdout, to; kwargs...)


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

function validated_options(; sortby, allocations, compact, bars, gc, columns, linechars, maxdepth, complement)
    sortby in SORTBY_OPTIONS ||
        throw(ArgumentError("sortby should be :time, :allocations, :ncalls, :name, or :firstexec, got $sortby"))
    linechars in (:unicode, :ascii) ||
        throw(ArgumentError("linechars should be :unicode or :ascii, got $linechars"))
    maxdepth >= 1 ||
        throw(ArgumentError("maxdepth should be at least 1, got $maxdepth"))
    # like 0.5, the most minimal selection also drops the header block
    header = !(compact && !allocations && columns === nothing)
    columns = resolve_columns(columns === nothing ? default_columns(allocations, compact, bars, gc) : columns)
    return TableOptions(
        sortby, columns, linechars === :ascii, maxdepth, complement, header,
        tree_guides(linechars)
    )
end

# whether any shown column belongs to the given merged header group
has_group(opts::TableOptions, group::String) = any(c -> c.group == group, opts.columns)

function show_table(
        io::IO, to::TimerOutput;
        sortby::Symbol = :time, allocations::Bool = true, compact::Bool = false,
        bars::Bool = true, gc::Bool = false, columns::Union{Nothing, AbstractVector{Symbol}} = nothing,
        linechars::Symbol = :unicode, maxdepth::Int = typemax(Int),
        complement::Bool = false, title::String = ""
    )
    opts = validated_options(; sortby, allocations, compact, bars, gc, columns, linechars, maxdepth, complement)

    Δt = time_ns() - to.start_time
    Δb = gc_bytes() - to.start_allocs
    ∑t, ∑b = totmeasured(to)

    # wall clock time and allocations not measured by any section
    extra = if complement
        untimed = Section(
            "~untimed~", 0, max(Δt - ∑t, 0), max(Δb - ∑b, 0), 0, typemax(Int64),
            Section[], nothing, nothing
        )
        ComplementRow(untimed, false)
    else
        nothing
    end

    totals = if opts.header
        (;
            time = string(
                strip(asciitime(prettytime(Δt), opts.ascii)), " / ", strip(prettypercent(∑t, Δt))
            ),
            alloc = string(strip(prettymemory(Δb)), " / ", strip(prettypercent(∑b, Δb))),
        )
    else
        nothing
    end
    return _show_table(io, to.root, ∑t, ∑b, opts, title, totals, extra)
end

# A bare section prints as a table too, but has no meaningful wall-clock
# reference, so no "% measured" subtitle.
function show_table(
        io::IO, s::Section;
        sortby::Symbol = :time, allocations::Bool = true, compact::Bool = false,
        bars::Bool = true, gc::Bool = false, columns::Union{Nothing, AbstractVector{Symbol}} = nothing,
        linechars::Symbol = :unicode, maxdepth::Int = typemax(Int),
        complement::Bool = false, title::String = ""
    )
    opts = validated_options(; sortby, allocations, compact, bars, gc, columns, linechars, maxdepth, complement)
    ∑t, ∑b = s.ncalls > 0 ? (s.time, s.allocs) : totmeasured(s)
    # `_show_table` renders the children of its root. Wrap the section in a
    # detached display-only root so the section itself is the first row.
    display_root = Section("", 0, 0, 0, 0, s.firstexec, Section[s], nothing, nothing)
    return _show_table(io, display_root, ∑t, ∑b, opts, title, nothing, nothing)
end

# the merged header row: contiguous runs of columns in the same group. If
# `content` is given, the run of a group renders `content[group]` instead of
# the group name — used for the "Tot / % measured" totals row, where the
# leading empty run carries the row label.
function group_header(columns::Vector{ColumnSpec}, content = nothing, row_label = "")
    cells = Any[]
    empty_run = 1 # the Section column
    i = 1
    put(span, data) = push!(cells, span == 1 ? data : MultiColumn(span, data))
    while i <= length(columns)
        group = columns[i].group
        if isempty(group)
            empty_run += 1
            i += 1
        else
            if empty_run > 0
                if isempty(cells) && !isempty(row_label)
                    put(empty_run, row_label)
                else
                    push!(cells, EmptyCells(empty_run))
                end
                empty_run = 0
            end
            j = i
            while j <= length(columns) && columns[j].group == group
                j += 1
            end
            data = content === nothing ? group : get(content, group, "")
            put(j - i, data)
            i = j
        end
    end
    empty_run > 0 && push!(cells, EmptyCells(empty_run))
    return cells
end

function _show_table(io::IO, s::Section, ∑t, ∑b, opts::TableOptions, title, totals, extra)
    rows = Vector{Vector{String}}()
    gray = Int[]
    heats = NTuple{2, Float64}[]
    table_rows!(rows, gray, heats, s, ∑t, ∑b, "", 1, opts, extra)

    labels = String["Section"; [c.label for c in opts.columns]]
    ncols = length(labels)
    with_groups = opts.header && any(c -> !isempty(c.group), opts.columns)

    # the totals go in a row underneath the column group headers they belong
    # to; without group headers they become a plain line above the table
    subtitle = ""
    column_labels = if with_groups
        # note: the outer container must not be a Vector{Any}, PrettyTables
        # only expands MultiColumn/EmptyCells cells for vectors of vectors
        label_rows = [group_header(opts.columns)]
        if totals !== nothing
            content = Dict("Time" => totals.time, "Allocations" => totals.alloc)
            push!(label_rows, group_header(opts.columns, content, "Tot / % measured:"))
        end
        push!(label_rows, labels)
        label_rows
    else
        totals === nothing || (subtitle = string("Tot / % measured: ", totals.time))
        [labels]
    end

    data = if isempty(rows)
        Matrix{String}(undef, 0, ncols)
    else
        permutedims(reduce(hcat, rows))
    end

    # complement rows are shown in gray (first match wins, so gray beats heat)
    highlighters = TextHighlighter[]
    if !isempty(gray)
        grayset = Set(gray)
        push!(highlighters, TextHighlighter((_, i, _) -> i in grayset, crayon"dark_gray"))
    end
    # the bar columns are colored by their share of the total
    heat_which = Dict{Int, Int}() # data column index -> which fraction (1 = time, 2 = allocs)
    for (k, c) in enumerate(opts.columns)
        if c === COLUMNS.time_bar
            heat_which[k + 1] = 1
        elseif c === COLUMNS.allocs_bar
            heat_which[k + 1] = 2
        end
    end
    if !isempty(heat_which)
        push!(
            highlighters, TextHighlighter(
                (_, i, j) -> haskey(heat_which, j),
                (h, _, i, j) -> heat_crayon(heats[i][heat_which[j]])
            )
        )
    end

    pretty_table(
        io, data;
        column_labels = column_labels,
        alignment = [:l; fill(:r, ncols - 1)],
        # underline the Time/Allocations column group headers
        table_format = if opts.ascii
            TextTableFormat(;
                borders = text_table_borders__compact,
                horizontal_line_at_merged_column_labels = true,
                @text__no_vertical_lines
            )
        else
            TextTableFormat(; horizontal_line_at_merged_column_labels = true, @text__no_vertical_lines)
        end,
        style = TextTableStyle(;
            title = crayon"bold",
            subtitle = crayon"dark_gray",
            first_line_merged_column_label = crayon"bold",
            # the totals row consists of merged label cells; the PrettyTables
            # default for those is gray and underlined
            merged_column_label = crayon"default",
            column_label = crayon"default"
        ),
        highlighters = highlighters,
        # crop to the display width in the REPL and on terminals so long
        # section names never make lines wrap (#166); the Section column is
        # shrunk first so the numeric columns survive
        fit_table_in_display_horizontally = get(io, :limit, io isa Base.TTY)::Bool,
        shrinkable_data_column = 1,
        shrinkable_column_minimum_width = 10,
        title = title,
        title_alignment = :c,
        subtitle = subtitle,
        subtitle_alignment = :c
    )
    return nothing
end
