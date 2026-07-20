########################
# Tables.jl interface  #
########################

# Timers are tables: one row per section, in depth-first insertion order, with
# the raw (unformatted) measurements. This makes e.g. `DataFrame(to)` and
# `CSV.write(file, to)` work directly.
#
# The `path` column joins the nesting with '/' for readability; use `depth`
# together with the row order to reconstruct the tree exactly.

const SectionRow = @NamedTuple{
    path::String, section::String, depth::Int,
    ncalls::Int64, time_ns::Int64, gc_time_ns::Int64, allocated_bytes::Int64, firstexec_ns::Int64,
}

Tables.istable(::Type{<:Union{TimerOutput, Section}}) = true
Tables.rowaccess(::Type{<:Union{TimerOutput, Section}}) = true

function Tables.rows(to::TimerOutput)
    rows = SectionRow[]
    for child in to.root.children
        _section_rows!(rows, child, "", 0)
    end
    return rows
end

# a bare section includes itself as the first row
Tables.rows(s::Section) = _section_rows!(SectionRow[], s, "", 0)


Tables.schema(::Union{TimerOutput, Section}) =
    Tables.Schema(fieldnames(SectionRow), fieldtypes(SectionRow))

function _section_rows!(rows::Vector{SectionRow}, s::Section, prefix::String, depth::Int)
    path = isempty(prefix) ? s.name : string(prefix, "/", s.name)
    push!(
        rows, (;
            path, section = s.name, depth,
            ncalls = s.ncalls, time_ns = s.time, gc_time_ns = s.gc_time,
            allocated_bytes = s.allocs, firstexec_ns = s.firstexec,
        )
    )
    for child in s.children
        _section_rows!(rows, child, path, depth + 1)
    end
    return rows
end
