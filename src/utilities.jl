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

    if value >= 100
        str = string(@sprintf("%.0f", value), units)
    elseif value >= 10
        str = string(@sprintf("%.1f", value), units)
    else
        str = string(@sprintf("%.2f", value), units)
    end
    return str
end

function prettymemory(b)
    if b < 1000
        value = -1
        str = string(b, "B")
    elseif b < 1000^2
        value, units = b / 1024, "KiB"
    elseif b < 1000^3
        value, units = b / 1024^2, "MiB"
    else
        value, units = b / 1024^3, "GiB"
    end


    if value >= 100
        str = string(@sprintf("%.0f", value), units)
    elseif value >= 10
        str = string(@sprintf("%.1f", value), units)
    elseif value >= 0
        str = string(@sprintf("%.2f", value), units)
    end
    return str
end

function prettypercent(nominator, denominator)
    value = nominator / denominator * 100
    if denominator == 0 && nominator == 0
        str = " - %"
    elseif denominator == 0
        str = "inf %"
    elseif value >= 100
        str = string(@sprintf("%.0f", value), "%")
    elseif value >= 10
        str = string(@sprintf("%.1f", value), "%")
    else
        str = string(@sprintf("%.2f", value), "%")
    end
    # Workaround...
    str == "100.0%" && (str = "100%")
    return str
end

