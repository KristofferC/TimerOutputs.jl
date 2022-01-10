###################
# Pretty Printing #
###################

function prettytime(t)
    if t < 1e3
        value, units = t, "ns"
    elseif t < 1e6
        value, units = t / 1e3, "μs"
    elseif t < 1e9
        value, units = t / 1e6, "ms"
    else
        value, units = t / 1e9, "s"
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
    else
        value, units = b / 1024^3, "GiB"
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

function prettypercent(nominator, denominator)
    value = nominator / denominator * 100

    if denominator == 0 && nominator == 0
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
        value, units = t / 1e6, "M"
    else
        value, units = t / 1e9, "B"
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

function rpad(
    s::Union{AbstractChar,AbstractString},
    n::Integer,
    p::Union{AbstractChar,AbstractString}=' ',
) :: String
    n = Int(n)::Int
    m = signed(n) - Int(textwidth(s))::Int
    m ≤ 0 && return string(s)
    l = textwidth(p)
    q, r = divrem(m, l)
    r == 0 ? string(s, p^q) : string(s, p^q, first(p, r))
end

#################
# Serialization #
#################

"""
    todict(to::TimerOutput) -> Dict{String, Any}

Converts a `TimerOutput` into a nested set of dictionaries, with keys and value types:

* `"n_calls"`: `Int`
* `"time_ns"`: `Int`
* `"allocated_bytes"`: `Int`
* `"total_allocated_bytes"`: `Int`
* `"total_time_ns"`: `Int`
* `"inner_timers"`: `Dict{String, Dict{String, Any}}`
"""
function todict(to::TimerOutput)
    return Dict{String,Any}(
        "n_calls" => ncalls(to),
        "time_ns" => time(to),
        "allocated_bytes" => allocated(to),
        "total_allocated_bytes" => totallocated(to),
        "total_time_ns" => tottime(to),
        "inner_timers" => Dict{String, Any}(k => todict(v) for (k,v) in to.inner_timers)
    )
end
