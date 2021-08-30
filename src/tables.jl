Tables.istable(::Type{TimerOutput}) = true
Tables.rowaccess(::Type{TimerOutput}) = true

struct TimerOutputRow
    name::Tuple{String,Vararg{String}}
    ncalls::Int
    time::Int
    allocated::Int
    totallocated::Int
    tottime::Int
    isleaf::Bool
end

function foreachrow(f, timer::TimerOutput, prefix::Tuple{Vararg{String}} = ())
    for k in sort!(collect(keys(timer.inner_timers)))
        to = timer.inner_timers[k]
        name = (prefix..., k)
        row = TimerOutputRow(
            name,
            ncalls(to),
            time(to),
            allocated(to),
            totallocated(to),
            tottime(to),
            isempty(to.inner_timers),
        )
        f(row)
        foreachrow(f, to, name)
    end
end

function Tables.rows(to::TimerOutput)
    table = TimerOutputRow[]
    foreachrow(to) do row
        push!(table, row)
    end
    return table
end

const TABLE_SCHEMA =
    Tables.Schema{fieldnames(TimerOutputRow),Tuple{fieldtypes(TimerOutputRow)...}}()

Tables.schema(::TimerOutput) = TABLE_SCHEMA
