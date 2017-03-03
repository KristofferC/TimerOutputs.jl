############
# TimeData #
############
type TimeData
    ncalls::Int
    time::UInt64
    allocs::UInt64
end

TimeData() = TimeData(0, 0, 0)

function Base.isless(self::TimeData, other::TimeData)
    if SORT_MODE == :time
        return self.time < other.time
    elseif SORT_MODE == :allocated
        return self.allocs < other.allocs
    elseif SORT_MODE == :ncalls
        return self.ncalls < other.ncalls
    else
        error("unexpected sort mode")
    end
end


###############
# TimerOutput #
###############
type TimerOutput
    start_data::TimeData
    accumulated_data::TimeData
    inner_timers::Dict{String, TimerOutput}
    timer_stack::Vector{TimerOutput}
    name::String
end

function TimerOutput(label::String = "root")
    start_data = TimeData(0, time_ns(), gc_bytes())
    accumulated_data = TimeData()
    inner_timers = Dict{String, TimerOutput}()
    timer_stack = TimerOutput[]
    return TimerOutput(start_data, accumulated_data, inner_timers, timer_stack, label)
end

Base.getindex(to::TimerOutput, name::String) = to.inner_timers[name]

Base.isless(self::TimerOutput, other::TimerOutput) = self.accumulated_data < other.accumulated_data

const DEFAULT_TIMER = TimerOutput()

# push! and pop!
function Base.push!(to::TimerOutput, label::String)
    if length(to.timer_stack) == 0 # Root section
        current_timer = to
    else # Not a root section
        current_timer = to.timer_stack[end]
    end
    timer = get!(current_timer.inner_timers, label, TimerOutput(label))
    push!(to.timer_stack, timer)
    return timer.accumulated_data
end

Base.pop!(to::TimerOutput) = pop!(to.timer_stack)

# Only sum the highest parents
function totmeasured(to::TimerOutput)
    t, b = UInt64(0), UInt64(0)
    for section in values(to.inner_timers)
        timedata = section.accumulated_data
        t += timedata.time
        b += timedata.allocs
    end
    return t, b
end

function longest_name(to::TimerOutput, indent = 0)
    m = length(to.name) + indent
    for inner_timer in values(to.inner_timers)
        m = max(m, longest_name(inner_timer, indent + 2))
    end
    return m
end

#######
# API #
#######

# Macro
macro timeit(args...)
    return timer_expr(args...)
end

#timer_expr(args...) = throw(ArgumentError("invalid macro usage for @timeit"))

timer_expr(label::String, ex::Expr) = timer_expr(:(TimerOutputs.DEFAULT_TIMER), label, ex)

function timer_expr(to::Union{Symbol, Expr}, label::String, ex::Expr)
    quote
        local accumulated_data = push!($(esc(to)), $(esc(label)))
        local b₀ = gc_bytes()
        local t₀ = time_ns()
        local val = $(esc(ex))
        accumulated_data.time += time_ns() - t₀
        accumulated_data.allocs += gc_bytes() - b₀
        accumulated_data.ncalls += 1
        pop!($(esc(to)))
        val
    end
end

reset_timer!() = reset_timer!(DEFAULT_TIMER)
function reset_timer!(to::TimerOutput)
    to.inner_timers = Dict{String, TimerOutput}()
    to.start_data = TimeData(0, time_ns(), gc_bytes())
    to.accumulated_data = TimeData()
    resize!(to.timer_stack, 0)
    return to
end

timeit(f::Function, label::String) = timeit(f, DEFAULT_TIMER, label)
function timeit(f::Function, to::TimerOutput, label::String)
    accumulated_data = push!(to, label)
    b₀ = gc_bytes()
    t₀ = time_ns()
    local val
    try
        val = f()
    finally
        accumulated_data.time += time_ns() - t₀
        accumulated_data.allocs += gc_bytes() - b₀
        accumulated_data.ncalls += 1
        pop!(to)
    end
    return val
end
