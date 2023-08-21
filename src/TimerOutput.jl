############
# TimeData #
############
struct TimeData
    ncalls::Int64
    time::Int64
    allocs::Int64
end
TimeData() = TimeData(0,0,0)

function Base.:+(self::TimeData, other::TimeData)
    TimeData(self.ncalls + self.ncalls,
             self.time + other.time,
             self.allocs + other.allocs)
end

mutable struct LList{T}
    const next::LList{T}
    const val::T
    LList{T}() where T = new{T}()
    LList(next::LList{T}, val::T) where T = new{T}(next, val)
end

function Base.show(io::IO, list::LList)
    print(io, LList, "(")
    first = true
    while isdefined(list, :next)
        first || print(io, ", ")
        first = false
        show(io, list.val)
        list = list.next
    end
    print(io, ")")
end

function Base.iterate(list::LList{T}, state::Union{Nothing, LList{T}}=nothing) where T
    if state === nothing
        state = list
    end
    if !isdefined(state, :next)
        return nothing
    end
    return (state.val, state.next)
end

Base.eltype(::LList{T}) where T = T
Base.IteratorSize(::Type{<:LList}) = Base.SizeUnknown()


###############
# TimerOutput #
###############
mutable struct TimerOutput
    const name::String
    const parent::Union{Nothing, TimerOutput}
    @atomic data::Union{Nothing, TimeData}
    @atomic children::LList{TimerOutput}

end
function TimerOutput(name::String = "root", parent=nothing)
    return TimerOutput(name, parent, nothing, LList{TimerOutput}())
end

# function Base.show(io::IO, to::TimerOutput)
#     print(io, TimerOutput, "(")
#     show(io, to.name)
#     print(io, ", ")
#     show(io, @atomic(to.data))
#     print(io, ", ")
#     show(io, @atomic(to.children))
#     print(io, ")")
# end

const TIMER = ScopedValue(TimerOutput())


function register!(to::TimerOutput)
    # Note: Don't call register twice
    parent = to.parent
    if parent === nothing
        return false
    end
    success = false
    old = @atomic :acquire parent.children
    while !success
        new = LList(old, to)
        old, success = @atomicreplace :acquire_release :acquire parent.children old => new
    end
    return true
end

function finish!(to::TimerOutput, t₀, b₀)
    data = TimeData(1, time_ns() - t₀, gc_bytes() - b₀)
    @atomic to.data = data
    register!(to)
end

# Only sum the highest parents
function totmeasured(to::TimerOutput)
    t, b = Int64(0), Int64(0)
    for child in to.children
        timedata = child.data
        t += timedata.time
        b += timedata.allocs
    end
    return t, b
end

function longest_name(to::TimerOutput, indent = 0)
    m = textwidth(to.name) + indent
    for child in to.children
        m = max(m, longest_name(child, indent + 2))
    end
    return m
end

#######
# API #
#######

# Accessors
ncalls(to::TimerOutput) = to.data.ncalls
allocated(to::TimerOutput) = to.data.allocs
time(to::TimerOutput) = to._data.time
totallocated(to::TimerOutput) = totmeasured(to)[2]
tottime(to::TimerOutput) = totmeasured(to)[1]

time() = time(TIMER[])
ncalls() = ncalls(TIMER[])
allocated() = allocated(TIMER[])
totallocated() = totmeasured(TIMER[])[2]
tottime() = totmeasured(TIMER[])[1]

get_defaulttimer() = TIMER[]
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

timer_expr(args...) = throw(ArgumentError("invalid macro usage for @timeit, use as @timeit label codeblock"))

function is_func_def(f)
    if isa(f, Expr) && (f.head === :function || Base.is_short_function_def(f))
        return true
    else
        return false
    end
end

function timer_expr(m::Module, is_debug::Bool, ex::Expr)
    is_func_def(ex) && return timer_expr_func(m, is_debug, ex, nothing)
    error("invalid macro usage for @timeit")
end

function timer_expr(m::Module, is_debug::Bool, label, ex::Expr)
    timer_expr(m, is_debug, string(label), ex)
end

function timer_expr(m::Module, is_debug::Bool, label::String, ex::Expr)
    is_func_def(ex) && return timer_expr_func(m, is_debug, ex, label)
    return esc(_timer_expr(m, is_debug, label, ex))
end

function _timer_expr(m::Module, is_debug::Bool, label, ex::Expr)
    @gensym b₀ t₀ val
    timeit_block = quote
        $scoped($(TIMER) => $(TimerOutput)($label, $(TIMER)[])) do # TODO can we have a macro form of this?
            $b₀ = $(gc_bytes)()
            $t₀ = $(time_ns)()
            $(Expr(:tryfinally,
                :($val = $ex),
                :($(finish!)($(TIMER)[], $t₀, $b₀))
            ))
            $val
        end
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

function timer_expr_func(m::Module, is_debug::Bool, expr::Expr, label=nothing)
    expr = macroexpand(m, expr)
    def = splitdef(expr)

    label === nothing && (label = string(def[:name]))

    def[:body] = if is_debug
        quote
            @inline function inner()
                $(def[:body])
            end
            $(_timer_expr(m, is_debug, label, :(inner())))
        end
    else
        _timer_expr(m, is_debug, label, def[:body])
    end

    return esc(combinedef(def))
end

reset_timer!() = reset_timer!(TIMER[])
function reset_timer!(to::TimerOutput)
    @atomic to.data = nothing
    @atomic to.children = LList{TimerOutput}()
    return to
end

function merge(self::TimerOutput, other::Union{TimerOutput, Nothing}=nothing)
    if other !== nothing
        @assert self.parent == other.parent
        @assert self.name == other.name

        data = self.data + other.data
    else
        data = self.data
    end

    accum = Dict{String, TimerOutput}()
    for child in self.children
        if !haskey(accum, child.name)
            accum[child.name] = merge(child)
            continue
        end
        accum[child.name] = merge(accum[child.name], child)
    end
    if other !== nothing
        for child in other.children
            if !haskey(accum, child.name)
                accum[child.name] = merge(child)
                continue
            end
            accum[child.name] = merge(accum[child.name], child)
        end
    end
    list = LList{TimerOutput}()
    for child in values(accum)
        list = LList(list, child)
    end
    return TimerOutput(self.name, self.parent, data, list)
end
