# Slightly modified from https://github.com/johnmyleswhite/Benchmarks.jl
# Benchmarks.jl is licensed under the MIT License:
# Copyright (c) 2015: John Myles White and other contributors.

const _sec_units = ["ns", "μs", "ms", "s "]
function prettyprint_nanoseconds(value::UInt64)
    if value < 1000
        return (1, value, 0)    # nanoseconds
    elseif value < 1000000
        mt = 2
    elseif value < 1000000000
        mt = 3
        # round to nearest # of microseconds
        value = div(value+500,1000)
    elseif value < 1000000000000
        mt = 4
        # round to nearest # of milliseconds
        value = div(value+500000,1000000)
    else
        # round to nearest # of seconds
        return (4, div(value+500000000,1000000000), 0)
    end
    frac::UInt64 = div(value,1000)
    return (mt, frac, value-(frac*1000))
end


function time_print(elapsedtime)
    mt, pptime, fraction = prettyprint_nanoseconds(elapsedtime)
    if fraction != 0
        return @sprintf("%4d.%03d %s", pptime, fraction, _sec_units[mt])
    else
        return @sprintf("%8d %s", pptime, _sec_units[mt])
    end
end