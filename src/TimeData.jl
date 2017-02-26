type TimeData
    ncalls::Int
    tottime::UInt64
end

ncalls(td::TimeData) = td.ncalls
tottime(td::TimeData) = td.tottime
Base.isless(self::TimeData, other::TimeData) = self.tottime < other.tottime

function reset!(td::TimeData)
    td.ncalls = 0
    td.tottime = 0
end