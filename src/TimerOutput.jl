############
# TimeData #
############
mutable struct TimeData
    ncalls::Int
    time::Int64
    allocs::Int64
end

Base.copy(td::TimeData) = TimeData(td.ncalls, td.time, td.allocs)
TimeData() = TimeData(0, 0, 0)

function Base.:+(self::TimeData, other::TimeData)
    TimeData(self.ncalls + other.ncalls,
             self.time + other.time,
             self.allocs + other.allocs)
end

###############
# TimerOutput #
###############
mutable struct TimerOutput
    start_data::TimeData
    accumulated_data::TimeData
    inner_timers::Dict{String,TimerOutput}
    timer_stack::Vector{TimerOutput}
    name::String
    flattened::Bool
    totmeasured::Tuple{Int64,Int64}
    prev_timer_label::String
    prev_timer::TimerOutput

    function TimerOutput(label::String = "root")
        start_data = TimeData(0, time_ns(), gc_bytes())
        accumulated_data = TimeData()
        inner_timers = Dict{String,TimerOutput}()
        timer_stack = TimerOutput[]
        timer = new(start_data, accumulated_data, inner_timers, timer_stack, label, false, (0, 0), "")
        timer.prev_timer = timer
    end

    # Jeez...
    TimerOutput(start_data, accumulated_data, inner_timers, timer_stack, name, flattened, totmeasured, prev_timer_label,
    prev_timer) = new(start_data, accumulated_data, inner_timers, timer_stack, name, flattened, totmeasured, prev_timer_label,
    prev_timer)

end

Base.copy(to::TimerOutput) = TimerOutput(copy(to.start_data), copy(to.accumulated_data), copy(to.inner_timers),
                                         copy(to.timer_stack), to.name, to.flattened, to.totmeasured, "", to)

const DEFAULT_TIMER = TimerOutput()

# push! and pop!
function Base.push!(to::TimerOutput, label::String)
    if length(to.timer_stack) == 0 # Root section
        current_timer = to
    else # Not a root section
        current_timer = to.timer_stack[end]
    end
    # Fast path
    if to.prev_timer_label == label
        timer = to.prev_timer
    else
        timer = get!(() -> TimerOutput(label), current_timer.inner_timers, label)
    end
    to.prev_timer_label = label
    to.prev_timer = timer

    push!(to.timer_stack, timer)
    return timer.accumulated_data
end

Base.pop!(to::TimerOutput) = pop!(to.timer_stack)

# Only sum the highest parents
function totmeasured(to::TimerOutput)
    t, b = Int64(0), Int64(0)
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

# Accessors
ncalls(to::TimerOutput)    = to.accumulated_data.ncalls
allocated(to::TimerOutput) = to.accumulated_data.allocs
time(to::TimerOutput) = to.accumulated_data.time
totallocated(to::TimerOutput) = totmeasured(to)[2]
tottime(to::TimerOutput) = totmeasured(to)[1]

time() = time(DEFAULT_TIMER)
ncalls() = ncalls(DEFAULT_TIMER)
allocated() = allocated(DEFAULT_TIMER)
totallocated() = totmeasured(DEFAULT_TIMER)[2]
tottime() = totmeasured(DEFAULT_TIMER)[1]

get_defaulttimer() = DEFAULT_TIMER
Base.@deprecate get_defaultimer get_defaulttimer

# Macro
macro timeit(args...)
    return timer_expr(__module__, false, args...)
end

macro timeit_debug(args...)
    if !isdefined(__module__, :timeit_debug_enabled)
        Core.eval(__module__, :(timeit_debug_enabled() = false))
    end

    return timer_expr(__module__, true, args...)
end

function enable_debug_timings(m::Module)
    if !getfield(m, :timeit_debug_enabled)()
        Core.eval(m, :(timeit_debug_enabled() = true))
    end
end
function disable_debug_timings(m::Module)
    if getfield(m, :timeit_debug_enabled)()
        Core.eval(m, :(timeit_debug_enabled() = false))
    end
end

timer_expr(args...) = throw(ArgumentError("invalid macro usage for @timeit, use as @timeit [to] label codeblock"))

function is_func_def(f)
    if isa(f, Expr) && (f.head === :function || Base.is_short_function_def(f))
        return true
    else
        return false
    end
end

function timer_expr(m::Module, is_debug::Bool, ex::Expr)
    is_func_def(ex) && return timer_expr_func(m, is_debug, :(TimerOutputs.DEFAULT_TIMER), ex)
    return timer_expr(m, is_debug, :(TimerOutputs.DEFAULT_TIMER), ex)
end

function timer_expr(m::Module, is_debug::Bool, label_or_to, ex::Expr)
    is_func_def(ex) && return timer_expr_func(m, is_debug, label_or_to, ex)
    return timer_expr(m, is_debug, :(TimerOutputs.DEFAULT_TIMER), label_or_to, ex)
end

function timer_expr_func(m::Module, is_debug::Bool, to, expr::Expr)
    if expr.args[1].head == :where
        wheres = expr.args[1].args[2:end]
        declaration = expr.args[1].args[1]
    else
        wheres = []
        declaration = expr.args[1]
    end
    if length(declaration.args) == 2 && declaration.head == :(::)
        T        = declaration.args[2]
        funcname = declaration.args[1].args[1]
        args     = declaration.args[1].args[2:end]
    else
        T        = Any
        funcname = declaration.args[1]
        args     = declaration.args[2:end]
    end
    body = expr.args[2]

    timeit_block = quote
        $(timeit)($(esc(to)), $(string(funcname))) do
            $(esc(body))
        end
    end

    # If this is a `@timeit_debug`, then we insert the bypass conditional into our timeit_block
    if is_debug
        timeit_block = quote
            if $(esc(m)).timeit_debug_enabled()
                $(timeit_block)
            else
                $(esc(body))
            end
        end
    end

    return quote
        function $(esc(funcname))($([esc(arg) for arg in args]...))::$(esc(T)) where {$([esc(wher) for wher in wheres]...)}
            $(timeit_block)
        end
    end
end

function do_accumulate!(accumulated_data, t₀, b₀)
    accumulated_data.time += time_ns() - t₀
    accumulated_data.allocs += gc_bytes() - b₀
    accumulated_data.ncalls += 1
end

function timer_expr(m::Module, is_debug::Bool, to::Union{Symbol,Expr}, label, ex::Expr)
    timeit_block = quote
        local accumulated_data = $(push!)($(esc(to)), $(esc(label)))
        local b₀ = $(gc_bytes)()
        local t₀ = $(time_ns)()
        local val
        $(Expr(:tryfinally,
            :(val = $(esc(ex))),
            quote
                $(do_accumulate!)(accumulated_data, t₀, b₀)
                $(pop!)($(esc(to)))
            end))
        val
    end

    if is_debug
        return quote
            if $(esc(m)).timeit_debug_enabled()
                $(timeit_block)
            else
                $(esc(ex))
            end
        end
    else
        return timeit_block
    end
end

reset_timer!() = reset_timer!(DEFAULT_TIMER)
function reset_timer!(to::TimerOutput)
    to.inner_timers = Dict{String,TimerOutput}()
    to.start_data = TimeData(0, time_ns(), gc_bytes())
    to.accumulated_data = TimeData()
    to.prev_timer_label = ""
    resize!(to.timer_stack, 0)
    return to
end

# We can remove this now that the @timeit macro is exception safe.
# Doesn't hurt to keep it for a while though
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

Base.haskey(to::TimerOutput, name::String) = haskey(to.inner_timers, name)
Base.getindex(to::TimerOutput, name::String) = to.inner_timers[name]

function flatten(to::TimerOutput)
    t, b = totmeasured(to)
    inner_timers = Dict{String,TimerOutput}()
    for inner_timer in values(to.inner_timers)
        _flatten!(inner_timer, inner_timers)
    end
    toc = copy(to)
    return TimerOutput(toc.start_data, toc.accumulated_data, inner_timers, TimerOutput[], "Flattened", true, (t, b), "", to)
end


function _flatten!(to::TimerOutput, inner_timers::Dict{String,TimerOutput})
    for inner_timer in values(to.inner_timers)
        _flatten!(inner_timer, inner_timers)
    end

    if haskey(inner_timers, to.name)
        timer = inner_timers[to.name]
        timer.accumulated_data += to.accumulated_data
    else
        toc = copy(to)
        toc.inner_timers = Dict{String,TimerOutput}()
        inner_timers[toc.name] = toc
    end
end
