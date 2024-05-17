############
# TimeData #
############
mutable struct TimeData
    ncalls::Int
    time::Int64
    allocs::Int64
    firstexec::Int64
end
TimeData(ncalls, time, allocs) = TimeData(ncalls, time, allocs, time)
Base.copy(td::TimeData) = TimeData(td.ncalls, td.time, td.allocs)
TimeData() = TimeData(0, 0, 0, time_ns())

function Base.:+(self::TimeData, other::TimeData)
    TimeData(self.ncalls + other.ncalls,
             self.time + other.time,
             self.allocs + other.allocs,
             min(self.firstexec, other.firstexec))
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
    enabled::Bool
    totmeasured::Tuple{Int64,Int64}
    prev_timer_label::String
    prev_timer::Union{TimerOutput,Nothing}

    function TimerOutput(label::String = "root")
        start_data = TimeData(0, time_ns(), gc_bytes())
        accumulated_data = TimeData()
        inner_timers = Dict{String,TimerOutput}()
        timer_stack = TimerOutput[]
        return new(start_data, accumulated_data, inner_timers, timer_stack, label, false, true, (0, 0), "", nothing)
    end

    # Jeez...
    TimerOutput(start_data, accumulated_data, inner_timers, timer_stack, name, flattened, enabled, totmeasured, prev_timer_label,
    prev_timer) = new(start_data, accumulated_data, inner_timers, timer_stack, name, flattened, enabled, totmeasured, prev_timer_label,
    prev_timer)

end

Base.copy(to::TimerOutput) = TimerOutput(copy(to.start_data), copy(to.accumulated_data), copy(to.inner_timers),
                                         copy(to.timer_stack), to.name, to.flattened, to.enabled, to.totmeasured, "", nothing)

const DEFAULT_TIMER = TimerOutput()
const _timers = Dict{String, TimerOutput}("Default" => DEFAULT_TIMER)
const _timers_lock = ReentrantLock() # needed for adding new timers on different threads
"""
    get_timer(name::String)

Returns the `TimerOutput` associated with `name`.
If no timers are associated with `name`, a new `TimerOutput` will be created.
"""
function get_timer(name::String)
    lock(_timers_lock) do
        if !haskey(_timers, name)
            _timers[name] = TimerOutput(name)
        end
        return _timers[name]
    end
end

# push! and pop!
function Base.push!(to::TimerOutput, label::String)
    if length(to.timer_stack) == 0 # Root section
        current_timer = to
    else # Not a root section
        current_timer = to.timer_stack[end]
    end
    # Fast path
    if current_timer.prev_timer_label == label
        timer = current_timer.prev_timer
    else
        maybe_timer = get(current_timer.inner_timers, label, nothing)
        # this could be implemented more elegant using
        # get!(() -> TimerOutput(label), current_timer.inner_timers, label)
        # however that causes lots of allocations in
        # julia v1.3
        if maybe_timer === nothing
            timer = TimerOutput(label)
            current_timer.inner_timers[label] = timer
        else
            timer = maybe_timer
        end
    end
    timer = timer::TimerOutput
    current_timer.prev_timer_label = label
    current_timer.prev_timer = timer

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
    m = textwidth(to.name) + indent
    for inner_timer in values(to.inner_timers)
        m = max(m, longest_name(inner_timer, indent + 2))
    end
    return m
end


# merging timer outputs
const merge_lock = ReentrantLock() # needed for merges of objects on different threads

Base.merge(self::TimerOutput, others::TimerOutput...) = merge!(TimerOutput(), self, others...)
function Base.merge!(self::TimerOutput, others::TimerOutput...; tree_point = String[])
    lock(merge_lock) do
        for other in others
            self.accumulated_data += other.accumulated_data
            its = self.inner_timers
            for point in tree_point
                its = its[point].inner_timers
            end
            _merge(its, other.inner_timers)
        end
        return self
    end
end
function _merge(self::Dict{String,TimerOutput}, other::Dict{String,TimerOutput})
    for key in keys(other)
        if haskey(self, key)
            self[key].accumulated_data += other[key].accumulated_data
            _merge(self[key].inner_timers, other[key].inner_timers)
        else
            self[key] = deepcopy(other[key])
        end
    end
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
    is_func_def(ex) && return timer_expr_func(m, is_debug, :($(TimerOutputs.DEFAULT_TIMER)), ex)
    return esc(_timer_expr(m, is_debug, :($(TimerOutputs).DEFAULT_TIMER), ex))
end

function timer_expr(m::Module, is_debug::Bool, label_or_to, ex::Expr)
    is_func_def(ex) && return timer_expr_func(m, is_debug, label_or_to, ex)
    return esc(_timer_expr(m, is_debug, :($(TimerOutputs).DEFAULT_TIMER), label_or_to, ex))
end

function timer_expr(m::Module, is_debug::Bool, label::String, ex::Expr)
    is_func_def(ex) && return timer_expr_func(m, is_debug, :($(TimerOutputs).DEFAULT_TIMER), ex, label)
    return esc(_timer_expr(m, is_debug, :($(TimerOutputs).DEFAULT_TIMER), label, ex))
end

function timer_expr(m::Module, is_debug::Bool, to, label, ex::Expr)
    is_func_def(ex) && return timer_expr_func(m, is_debug, to, ex, label)
    return esc(_timer_expr(m, is_debug, to, label, ex))
end

function _timer_expr(m::Module, is_debug::Bool, to::Union{Symbol, Expr, TimerOutput}, label, ex::Expr)
    @gensym local_to enabled accumulated_data b₀ t₀ val
    timeit_block = quote
        $local_to = $to
        $enabled = $local_to.enabled
        if $enabled
            $accumulated_data = $(push!)($local_to, $label)
        end
        $b₀ = $(gc_bytes)()
        $t₀ = $(time_ns)()
        $(Expr(:tryfinally,
            :($val = $ex),
            quote
                if $enabled
                    $(do_accumulate!)($accumulated_data, $t₀, $b₀)
                    $(pop!)($local_to)
                end
            end))
        $val
    end

    if is_debug
        return quote
            if $m.timeit_debug_enabled()
                $timeit_block
            else
                $ex
            end
        end
    else
        return timeit_block
    end
end

function timer_expr_func(m::Module, is_debug::Bool, to, expr::Expr, label=nothing)
    expr = macroexpand(m, expr)
    def = splitdef(expr)

    label === nothing && (label = string(def[:name]))

    def[:body] = if is_debug
        quote
            @inline function inner()
                $(def[:body])
            end
            $(_timer_expr(m, is_debug, to, label, :(inner())))
        end
    else
        _timer_expr(m, is_debug, to, label, def[:body])
    end

    return esc(combinedef(def))
end

function do_accumulate!(accumulated_data, t₀, b₀)
    accumulated_data.time += time_ns() - t₀
    accumulated_data.allocs += gc_bytes() - b₀
    accumulated_data.ncalls += 1
end


reset_timer!() = reset_timer!(DEFAULT_TIMER)
function reset_timer!(to::TimerOutput)
    to.inner_timers = Dict{String,TimerOutput}()
    to.start_data = TimeData(0, time_ns(), gc_bytes())
    to.accumulated_data = TimeData()
    to.prev_timer_label = ""
    to.prev_timer = nothing
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
    return TimerOutput(toc.start_data, toc.accumulated_data, inner_timers, TimerOutput[], "Flattened", true, true, (t, b), "", to)
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

enable_timer!(to::TimerOutput=DEFAULT_TIMER) = to.enabled = true
disable_timer!(to::TimerOutput=DEFAULT_TIMER) = to.enabled = false


# Macro to selectively disable timer for expression
macro notimeit(args...)
    notimeit_expr(args...)
end

# Default function throws an error for the benefit of the user
notimeit_expr(args...) = throw(ArgumentError("invalid macro usage for @notimeit, use as @notimeit [to] codeblock"))

complement!() = complement!(DEFAULT_TIMER)
function complement!(to::TimerOutput)
    if length(to.inner_timers) == 0
        return nothing
    end
    tot_time = to.accumulated_data.time
    tot_allocs = to.accumulated_data.allocs
    for timer in values(to.inner_timers)
        tot_time -= timer.accumulated_data.time
        tot_allocs -= timer.accumulated_data.allocs
        complement!(timer)
    end
    tot_time = max(tot_time, 0)
    tot_allocs = max(tot_allocs, 0)
    if !(to.name in ["root", "Flattened"])
        name = string("~", to.name, "~")
        timer = TimerOutput(to.start_data, TimeData(max(1,to.accumulated_data.ncalls), tot_time, tot_allocs), Dict{String,TimerOutput}(), TimerOutput[], name, false, true, (tot_time, tot_allocs), to.name, to)
        to.inner_timers[name] = timer
    end
    return to
end

# If @notimeit was called without a TimerOutput instance, use default timer
notimeit_expr(ex::Expr) = notimeit_expr(:($(TimerOutputs.DEFAULT_TIMER)), ex)

# Disable timer, evaluate expression, restore timer to previous value, and return expression result
function notimeit_expr(to, ex::Expr)
    return quote
        local to = $(esc(to))
        local enabled = to.enabled
        $(disable_timer!)(to)
        local val
        $(Expr(:tryfinally,
            :(val = $(esc(ex))),
            quote
                if enabled
                    $(enable_timer!)(to)
                end
            end))
        val
    end
end
