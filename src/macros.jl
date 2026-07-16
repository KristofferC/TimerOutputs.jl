########################################
# @timeit, @timeit_debug and @notimeit #
########################################

# All macro forms normalize to (to, label, ex):
#
#   @timeit label ex
#   @timeit to label ex
#   @timeit [to|label] function f() ... end   (label defaults to the function name)
#
# `to` and `label` may be arbitrary expressions evaluated at run time. The user
# expression is spliced into an enabled branch (wrapped in a raw
# `Expr(:tryfinally)` so timing is exception safe) and a disabled branch (a
# bare copy). Unlike surface `try` the wrapper introduces no scope block, so
# assignments, `return`, `break` and `continue` behave as in the unwrapped
# code. When `isenabled(to)` folds to a compile-time `false` the enabled branch
# is dead and the whole thing reduces to just the expression.

"""
    @timeit [to::TimerOutput] label codeblock
    @timeit [to::TimerOutput] [label] function ... end

Time the code block or function body under `label`, accumulating into `to`
(the default timer if not given). Returns the value of the timed expression.
"""
macro timeit(args...)
    return timer_expr(__source__, __module__, false, args...)
end

"""
    @timeit_debug [to::TimerOutput] label codeblock

Like [`@timeit`](@ref), but compiled away unless debug timings are enabled for
the enclosing module with `TimerOutputs.enable_debug_timings(mod)`.
"""
macro timeit_debug(args...)
    if !isdefined(__module__, :timeit_debug_enabled)
        Core.eval(__module__, :(timeit_debug_enabled() = false))
    end
    return timer_expr(__source__, __module__, true, args...)
end

function enable_debug_timings(m::Module)
    return if !getfield(m, :timeit_debug_enabled)()
        Core.eval(m, :(timeit_debug_enabled() = true))
    end
end
function disable_debug_timings(m::Module)
    return if getfield(m, :timeit_debug_enabled)()
        Core.eval(m, :(timeit_debug_enabled() = false))
    end
end

const TIMEIT_USAGE = "invalid macro usage for @timeit, use as @timeit [to] label codeblock"

default_timer_expr() = :($(TimerOutputs).DEFAULT_TIMER)

timer_expr(::LineNumberNode, ::Module, ::Bool, args...) = throw(ArgumentError(TIMEIT_USAGE))

# one macro argument: only valid for function definitions
function timer_expr(source::LineNumberNode, mod::Module, is_debug::Bool, ex)
    is_func_def(ex) || throw(ArgumentError(TIMEIT_USAGE))
    return timed_function_expr(source, mod, is_debug, default_timer_expr(), nothing, ex)
end

# two macro arguments: (label, ex), or for function definitions (to, funcdef)
# unless the first argument is a literal label
function timer_expr(source::LineNumberNode, mod::Module, is_debug::Bool, to_or_label, ex)
    if is_func_def(ex)
        if to_or_label isa String
            return timed_function_expr(source, mod, is_debug, default_timer_expr(), to_or_label, ex)
        else
            return timed_function_expr(source, mod, is_debug, to_or_label, nothing, ex)
        end
    end
    return timed_block_expr(source, mod, is_debug, default_timer_expr(), to_or_label, ex)
end

# three macro arguments: (to, label, ex)
function timer_expr(source::LineNumberNode, mod::Module, is_debug::Bool, to, label, ex)
    if is_func_def(ex)
        return timed_function_expr(source, mod, is_debug, to, label, ex)
    end
    return timed_block_expr(source, mod, is_debug, to, label, ex)
end

function is_func_def(ex)
    return ex isa Expr && (ex.head === :function || Base.is_short_function_def(ex))
end

# The full timed expression: run `ex` under section `label` of timer `to`,
# accumulating into a try/finally so it is exception safe, and evaluating to
# the value of `ex`. All functions are interpolated as objects so this works in
# any module.
#
# `ex` is spliced verbatim into both an enabled (timed) branch and a disabled
# branch. When `isenabled(to)` folds to a compile-time `false` — a
# `NoTimerOutput`, or a debug-disabled `@timeit_debug` — the enabled branch is
# dead and the whole thing reduces to a bare `ex` with no try/finally. That
# keeps `NoTimerOutput` genuinely zero-overhead, including on Julia 1.10 which
# does not elide an empty try/finally. Splicing `ex` verbatim (rather than
# behind a closure or temporary) also preserves its line numbers and lets
# `return`, `break`, `continue` and assignments behave as in the unwrapped code.
function timed_section(to, label, ex)
    @gensym to_local enabled data b₀ t₀
    cleanup = quote
        $(do_accumulate!)($data, $t₀, $b₀)
        $(pop!)($to_local)
    end
    return quote
        $to_local = $to
        $enabled = $(isenabled)($to_local)
        if $enabled
            $data = $(push!)($to_local, $label)
            $b₀ = $(gc_bytes)()
            $t₀ = $(time_ns)()
            $(Expr(:tryfinally, ex, cleanup))
        else
            $ex
        end
    end
end

# gate `core` behind the per-module debug switch, falling back to a bare `ex`
# so a disabled `@timeit_debug` compiles away
function debug_gated(mod::Module, core, ex)
    return quote
        if $mod.timeit_debug_enabled()
            $core
        else
            $ex
        end
    end
end

# `@timeit to label ex` for code blocks. The whole expression is escaped so the
# user code (and its line numbers) survives verbatim into stacktraces and coverage.
function timed_block_expr(source::LineNumberNode, mod::Module, is_debug::Bool, to, label, ex)
    core = timed_section(to, label, ex)
    is_debug && (core = debug_gated(mod, core, ex))
    return Expr(:block, source, esc(core))
end

# an (unescaped) expression that times `ex` and evaluates to its value
function timed_value_expr(mod::Module, is_debug::Bool, to, label, ex)
    core = timed_section(to, label, ex)
    is_debug && (core = debug_gated(mod, core, ex))
    return core
end

# `@timeit [to] [label] function f() ... end`
function timed_function_expr(source::LineNumberNode, mod::Module, is_debug::Bool, to, label, ex)
    ex = macroexpand(mod, ex)
    def = splitdef(ex)
    if label === nothing
        # anonymous functions get a file:line label
        label = haskey(def, :name) ? string(def[:name]) : string(source.file, ":", source.line)
    end
    body = def[:body]
    wrapped = if is_debug
        # the closure lets the debug-disabled branch reduce to a plain call
        quote
            @inline function inner()
                $body
            end
            $(timed_value_expr(mod, true, to, label, :(inner())))
        end
    else
        timed_value_expr(mod, false, to, label, body)
    end
    # remove line numbers of the wrapper code, but keep those of the user body
    # so stacktraces and coverage point into user code, and add the macro call
    # site at the top
    remove_linenums_keep!(wrapped, body)
    pushfirst!(wrapped.args, source)
    def[:body] = wrapped
    return esc(combinedef(def))
end

# Base.remove_linenums!, except the subtree `keep` is left untouched
function remove_linenums_keep!(ex, keep)
    if ex isa Expr && ex !== keep
        if ex.head === :block || ex.head === :quote
            filter!(x -> !(x isa LineNumberNode), ex.args)
        end
        for arg in ex.args
            remove_linenums_keep!(arg, keep)
        end
    end
    return ex
end

#############
# @notimeit #
#############

"""
    @notimeit [to] codeblock

Evaluate the code block with the timer disabled, restoring its previous state
afterwards.
"""
macro notimeit(args...)
    return notimeit_expr(args...)
end

notimeit_expr(args...) = throw(ArgumentError("invalid macro usage for @notimeit, use as @notimeit [to] codeblock"))

notimeit_expr(ex::Expr) = notimeit_expr(default_timer_expr(), ex)

function notimeit_expr(to, ex::Expr)
    return quote
        local to = $(esc(to))
        local enabled = $(isenabled)(to)
        $(disable_timer!)(to)
        local val
        $(
            Expr(
                :tryfinally,
                :(val = $(esc(ex))),
                quote
                    if enabled
                        $(enable_timer!)(to)
                    else
                        $(disable_timer!)(to)
                    end
                end
            )
        )
        val
    end
end
