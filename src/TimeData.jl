type TimeData
    ncalls::Int
    tottime::UInt64
    totallocs::UInt64
end

ncalls(td::TimeData) = td.ncalls
tottime(td::TimeData) = td.tottime
totallocs(td::TimeData) = td.totallocs

function Base.isless(self::TimeData, other::TimeData)
    if SORT_MODE == :time
        return tottime(self) < tottime(other)
    elseif SORT_MODE == :allocated
        return totallocs(self) < totallocs(other)
    else
        error("unexpected sort mode")
    end
end

function reset!(td::TimeData)
    td.ncalls = 0
    td.tottime = 0
    td.totallocs = 0
end
