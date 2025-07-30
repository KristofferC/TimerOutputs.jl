print_timer(; kwargs...) = print_timer(stdout; kwargs...)
print_timer(to::TimerOutput; kwargs...) = print_timer(stdout, to; kwargs...)
print_timer(io::IO; kwargs...) = print_timer(io, DEFAULT_TIMER; kwargs...)
print_timer(io::IO, to::TimerOutput; kwargs...) = (show(io, to; kwargs...); println(io))

function _extract_table_data(to::TimerOutput, sortby::Symbol, root_time_total::Int64, root_alloc_total::Int64, indent_level::Int = 0)
    sections = String[]
    ncalls_data = Int[]
    time_data = Int64[]
    time_pct_data = Float64[]
    time_avg_data = Float64[]
    alloc_data = Int64[]
    alloc_pct_data = Float64[]
    alloc_avg_data = Float64[]

    # Sort sections
    rev = !in(sortby, [:name, :firstexec])
    by(x) = sortf(x, sortby)
    sorted_timers = sort!(collect(values(to.inner_timers)); rev = rev, by = by)

    for timer in sorted_timers
        # Add indentation for nested sections
        section_name = "  "^indent_level * timer.name

        push!(sections, section_name)
        push!(ncalls_data, timer.accumulated_data.ncalls)
        push!(time_data, timer.accumulated_data.time)
        push!(time_pct_data, root_time_total > 0 ? 100.0 * timer.accumulated_data.time / root_time_total : 0.0)
        push!(time_avg_data, timer.accumulated_data.ncalls > 0 ? timer.accumulated_data.time ÷ timer.accumulated_data.ncalls : 0)
        push!(alloc_data, timer.accumulated_data.allocs)
        push!(alloc_pct_data, root_alloc_total > 0 ? 100.0 * timer.accumulated_data.allocs / root_alloc_total : 0.0)
        push!(alloc_avg_data, timer.accumulated_data.ncalls > 0 ? timer.accumulated_data.allocs ÷ timer.accumulated_data.ncalls : 0)

        # Recursively add nested timers
        if !isempty(timer.inner_timers)
            nested_sections, nested_ncalls, nested_time, nested_time_pct, nested_time_avg,
                nested_alloc, nested_alloc_pct, nested_alloc_avg = _extract_table_data(timer, sortby, root_time_total, root_alloc_total, indent_level + 1)

            append!(sections, nested_sections)
            append!(ncalls_data, nested_ncalls)
            append!(time_data, nested_time)
            append!(time_pct_data, nested_time_pct)
            append!(time_avg_data, nested_time_avg)
            append!(alloc_data, nested_alloc)
            append!(alloc_pct_data, nested_alloc_pct)
            append!(alloc_avg_data, nested_alloc_avg)
        end
    end

    return sections, ncalls_data, time_data, time_pct_data, time_avg_data, alloc_data, alloc_pct_data, alloc_avg_data
end

Base.show(to::TimerOutput; kwargs...) = show(stdout, to; kwargs...)
function Base.show(io::IO, to::TimerOutput; allocations::Bool = true, sortby::Symbol = :time, linechars::Symbol = :unicode, compact::Bool = false, title::String = "")
    sortby in (:time, :ncalls, :allocations, :name, :firstexec) || throw(ArgumentError("sortby should be :time, :allocations, :ncalls, :name, or :firstexec, got $sortby"))
    linechars in (:unicode, :ascii) || throw(ArgumentError("linechars should be :unicode or :ascii, got $linechars"))

    # Calculate total measurements
    t₀, b₀ = to.start_data.time, to.start_data.allocs
    t₁, b₁ = time_ns(), gc_bytes()
    Δt, Δb = t₁ - t₀, b₁ - b₀
    ∑t, ∑b = to.flattened ? to.totmeasured : totmeasured(to)

    # Extract table data
    if isempty(to.inner_timers)
        println(io, "No sections recorded.")
        return
    end

    sections, ncalls_data, time_data, time_pct_data, time_avg_data,
        alloc_data, alloc_pct_data, alloc_avg_data = _extract_table_data(to, sortby, ∑t, ∑b)

    # Format the data for display
    time_strings = [prettytime(t) for t in time_data]
    time_pct_strings = [prettypercent(pct, 100.0) for pct in time_pct_data]
    time_avg_strings = [prettytime(t) for t in time_avg_data]
    alloc_strings = [prettymemory(a) for a in alloc_data]
    alloc_pct_strings = [prettypercent(pct, 100.0) for pct in alloc_pct_data]
    alloc_avg_strings = [prettymemory(a) for a in alloc_avg_data]

    # Build table data matrix
    data_cols = [sections, ncalls_data, time_strings, time_pct_strings]

    if !compact
        push!(data_cols, time_avg_strings)
    end

    if allocations
        empty_col = fill("   ", length(sections))  # Use spaces to create wider separation
        push!(data_cols, empty_col)
        push!(data_cols, alloc_strings)
        push!(data_cols, alloc_pct_strings)

        if !compact
            push!(data_cols, alloc_avg_strings)
        end
    end
    table_data = reduce(hcat, data_cols)

    if compact
        if allocations
            println(io, "Total measured: $(prettytime(Δt)) / $(prettymemory(Δb))")
        else
            println(io, "Total measured: $(prettytime(Δt))")
        end
        println(io)

        column_labels = ["Section", "ncalls", "time", "%tot"]

        if allocations
            append!(column_labels, ["   ", "alloc", "%tot"])
        else
        end
    else
        row1 = []
        push!(row1, EmptyCells(2))

        time_cols = compact ? 2 : 3
        push!(row1, MultiColumn(time_cols, "Time (tot / % meas)"))

        if allocations
            push!(row1, EmptyCells(1))
            alloc_cols = compact ? 2 : 3
            push!(row1, MultiColumn(alloc_cols, "Allocations  (tot / % meas)"))
        end

        row2 = Any["", ""] # MultiColumn(2, "Tot / % measured:")]
        measured_pct_time = ∑t > 0 ? prettypercent(∑t, Δt; dolpad = false) : "  -%"
        time_measured = "$(prettytime(Δt)) / $measured_pct_time"
        if !compact
            push!(row2, MultiColumn(3, time_measured))
            # push!(row2, "")
        else
            push!(row2, time_measured)
        end

        if allocations
            push!(row2, "   ")
            measured_pct_alloc = ∑b > 0 ? prettypercent(∑b, Δb; dolpad = false) : "  -%"
            alloc_measured = "$(prettymemory(Δb)) / $measured_pct_alloc"
            if !compact
                push!(row2, MultiColumn(3, alloc_measured))

            else
                push!(row2, alloc_measured)
            end
        end

        # Row 3: Empty line
        total_cols = 5 + (compact ? 0 : 1) + (allocations ? (2 + (compact ? 0 : 1)) : 0)
        row3 = fill("", total_cols)

        row4 = ["Section", "ncalls", "time", "%tot"]
        if !compact
            push!(row4, "avg")
        end
        if allocations
            push!(row4, "   ")
            append!(row4, ["alloc", "%tot"])
            if !compact
                push!(row4, "avg")
            end
        end

        column_labels = [row1, row2, row3, row4]
    end

    table_format = TextTableFormat(;
        @text__no_vertical_lines
    )

    alignment_array = [:l, :r, :r, :r]
    if !compact
        push!(alignment_array, :r)
    end
    if allocations
        push!(alignment_array, :c) # empty col
        push!(alignment_array, :r)
        push!(alignment_array, :r)
        if !compact
            push!(alignment_array, :r)
        end
    end

    return pretty_table(
        io, table_data;
        column_labels = column_labels,
        merge_column_label_cells = :auto,
        show_omitted_cell_summary = false,
        alignment = alignment_array,
        table_format = table_format,
        title = !isempty(title) ? title : ""
    )
end

function sortf(x, sortby)
    sortby == :time        && return x.accumulated_data.time
    sortby == :ncalls      && return x.accumulated_data.ncalls
    sortby == :allocations && return x.accumulated_data.allocs
    sortby == :name        && return x.name
    sortby == :firstexec   && return x.accumulated_data.firstexec
    error("internal error")
end
