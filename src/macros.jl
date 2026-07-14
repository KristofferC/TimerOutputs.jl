######################################################
# @timeit, @timeit_debug, @timeit_all and @notimeit  #
######################################################

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

###############
# @timeit_all #
###############

"""
    @timeit_all [to::TimerOutput] [label] codeblock
    @timeit_all [to::TimerOutput] [label] function ... end

Like [`@timeit`](@ref), but additionally times every statement, recursing into
`for`, `while`, `if`, `let` and `try` blocks and nested function definitions.
Statements are labeled `file:line: code`. Wrap a statement in
[`@notimeit`](@ref) to exclude it.
"""
macro timeit_all(args...)
    return timeit_all_expr(__source__, __module__, args...)
end

const TIMEIT_ALL_USAGE = "invalid macro usage for @timeit_all, use as @timeit_all [to] [label] codeblock"

timeit_all_expr(::LineNumberNode, ::Module, args...) = throw(ArgumentError(TIMEIT_ALL_USAGE))

function timeit_all_expr(source::LineNumberNode, mod::Module, ex)
    return timeit_all_expr(source, mod, default_timer_expr(), nothing, ex)
end

# a literal string is a label, anything else is the timer
function timeit_all_expr(source::LineNumberNode, mod::Module, to_or_label, ex)
    if to_or_label isa String
        return timeit_all_expr(source, mod, default_timer_expr(), to_or_label, ex)
    end
    return timeit_all_expr(source, mod, to_or_label, nothing, ex)
end

function timeit_all_expr(source::LineNumberNode, mod::Module, to, label, ex)
    ex isa Expr || throw(ArgumentError(TIMEIT_ALL_USAGE))
    if is_func_def(ex)
        return esc(instrument_function_def(source, mod, to, label, ex))
    end
    # bind the timer to a local once so every statement shares the same object,
    # even when `to` has side effects or is reassigned inside the block
    @gensym to_local
    instrumented = instrument(mod, to_local, ex, source)
    if label === nothing
        body = Expr(:block, :($to_local = $to), instrumented)
        return Expr(:block, source, esc(body))
    end
    body = Expr(:block, :($to_local = $to), timed_section(to_local, label, instrumented))
    return Expr(:block, source, esc(body))
end

# Like `timed_function_expr` but with the body instrumented per statement, and
# unescaped so nested function definitions compose.
function instrument_function_def(source::LineNumberNode, mod::Module, to, label, ex::Expr)
    def = splitdef(ex)
    if label === nothing
        label = haskey(def, :name) ? string(def[:name]) : string(source.file, ":", source.line)
    end
    # bind the timer once per call so every statement shares the same object
    @gensym to_local
    body = instrument(mod, to_local, def[:body], source)
    wrapped = timed_value_expr(mod, false, to_local, label, body)
    remove_linenums_keep!(wrapped, body)
    pushfirst!(wrapped.args, :($to_local = $to))
    pushfirst!(wrapped.args, source)
    def[:body] = wrapped
    return combinedef(def)
end

function instrument(mod::Module, to, ex, line::LineNumberNode)
    if ex isa Expr && ex.head === :block
        return instrument_block(mod, to, ex, line)
    end
    return instrument_stmt(mod, to, ex, line)
end

function instrument_block(mod::Module, to, block::Expr, line::LineNumberNode)
    args = Any[]
    for arg in block.args
        if arg isa LineNumberNode
            line = arg
            push!(args, arg)
        else
            push!(args, instrument_stmt(mod, to, arg, line))
        end
    end
    return Expr(:block, args...)
end

# Statement heads spliced verbatim: control transfer may not move inside the
# `tryfinally`, and declarations/definitions must stay at their scope level.
# `return` is handled specially in `instrument_stmt`: its operand is timed while
# the transfer itself stays outside the wrapper.
const SKIPPED_STMT_HEADS = (
    :break, :continue, :symboliclabel, :symbolicgoto,
    :local, :global, :const, :import, :using, :export, :meta,
    :struct, :abstract, :primitive, :module, :macro, :toplevel,
)

# TimerOutputs' own macros manage their own sections
const SKIPPED_STMT_MACROS = (
    Symbol("@timeit"), Symbol("@timeit_debug"), Symbol("@timeit_all"), Symbol("@notimeit"),
)

function macro_name(ex::Expr)
    name = ex.args[1]
    if name isa Expr && name.head === :.
        name = name.args[end]
    end
    if name isa QuoteNode
        name = name.value
    end
    if name isa GlobalRef
        name = name.name
    end
    return name
end

# Jumping across a `tryfinally` boundary is a lowering error, so a statement
# containing a goto or label is left uninstrumented.
function has_goto(ex)
    ex isa Expr || return false
    (ex.head === :symboliclabel || ex.head === :symbolicgoto) && return true
    if ex.head === :macrocall
        name = macro_name(ex)
        (name === Symbol("@goto") || name === Symbol("@label")) && return true
    end
    return any(has_goto, ex.args)
end

function instrument_stmt(mod::Module, to, ex, line::LineNumberNode)
    ex isa Expr || return ex
    head = ex.head
    head in SKIPPED_STMT_HEADS && return ex
    head === :macrocall && macro_name(ex) in SKIPPED_STMT_MACROS && return ex
    has_goto(ex) && return ex
    # `return e`: keep the control transfer verbatim but time its operand
    if head === :return
        if length(ex.args) == 1 && ex.args[1] isa Expr
            operand = instrument_inner(mod, to, ex.args[1], line)
            return Expr(:return, timed_value_expr(mod, false, to, stmt_label(ex, line), operand))
        end
        return ex
    end
    head === :block && return instrument_block(mod, to, ex, line)
    is_func_def(ex) && return instrument_function_def(line, mod, to, nothing, ex)
    return timed_stmt_expr(to, stmt_label(ex, line), line, instrument_inner(mod, to, ex, line))
end

# recurse into the sub-blocks of control flow, leaving everything else alone
function instrument_inner(mod::Module, to, ex, line::LineNumberNode)
    ex isa Expr || return ex
    head = ex.head
    if head === :for || head === :while || head === :let
        return Expr(head, ex.args[1], instrument(mod, to, ex.args[2], line))
    elseif head === :if || head === :elseif
        args = copy(ex.args)
        for i in 2:length(args) # args[1] is the condition
            a = args[i]
            if a isa Expr && a.head === :elseif
                args[i] = instrument_inner(mod, to, a, line)
            elseif a isa Expr && a.head === :block
                args[i] = instrument_block(mod, to, a, line)
            end
        end
        return Expr(head, args...)
    elseif head === :try
        return Expr(:try, Any[a isa Expr && a.head === :block ? instrument_block(mod, to, a, line) : a for a in ex.args]...)
    elseif head === :block
        return instrument_block(mod, to, ex, line)
    elseif head === :(=) && !is_func_def(ex)
        return Expr(:(=), ex.args[1], instrument_inner(mod, to, ex.args[2], line))
    elseif head === :macrocall
        # `@inbounds for`, `@simd for`, `@views begin`, ... wrap control flow
        # whose body must still be instrumented. Recurse into the arguments,
        # leaving TimerOutputs' own macros (and `@notimeit`) untouched.
        macro_name(ex) in SKIPPED_STMT_MACROS && return ex
        return Expr(:macrocall, Any[a isa Expr ? instrument_inner(mod, to, a, line) : a for a in ex.args]...)
    end
    return ex
end

# One section around one statement. The statement's line number is restated
# inside the section so stacktraces point at user code, while the section's own
# bookkeeping code is stripped of line info.
function timed_stmt_expr(to, label::String, line::LineNumberNode, stmt)
    inner = Expr(:block, line, stmt)
    wrapped = timed_section(to, label, inner)
    remove_linenums_keep!(wrapped, inner)
    return wrapped
end

const STMT_LABEL_WIDTH = 60

function stmt_label(ex::Expr, line::LineNumberNode)
    prefix = string(basename(string(line.file)), ":", line.line, ": ")
    # Keep the whole `file:line:` prefix so distinct statements never collapse to
    # the same key (a long basename would otherwise truncate away line and code);
    # only the trailing code is shortened to fit the width.
    room = STMT_LABEL_WIDTH - textwidth(prefix)
    room <= 0 && return prefix
    return string(prefix, truncate_width(stmt_code(ex), room))
end

# a short single-line rendering of a statement for its section label; for
# control-flow constructs only the header is shown, not the (possibly huge) body
function stmt_code(ex::Expr)
    head = ex.head
    if head === :for
        return string("for ", stmt_string(ex.args[1]))
    elseif head === :while
        return string("while ", stmt_string(ex.args[1]))
    elseif head === :if
        return string("if ", stmt_string(ex.args[1]))
    elseif head === :let
        bindings = ex.args[1]
        if bindings isa Expr && bindings.head === :block && isempty(bindings.args)
            return "let"
        end
        return string("let ", stmt_string(bindings))
    elseif head === :try
        return "try"
    elseif head === :macrocall
        inner = ex.args[end]
        if inner isa Expr && inner.head in (:for, :while, :if, :let, :try)
            return string(stmt_string(ex.args[1]), " ", stmt_code(inner))
        end
    end
    return stmt_string(ex)
end

# single-line rendering of a statement for use in a section label
function stmt_string(ex)
    ex isa Expr || return string(ex)
    return join(split(string(strip_linenums!(copy(ex)))), " ")
end

# Base.remove_linenums!, but also blanks the line info of macro calls so they
# don't stringify as `#= file:line =#` comments
function strip_linenums!(ex::Expr)
    if ex.head === :macrocall && length(ex.args) >= 2 && ex.args[2] isa LineNumberNode
        ex.args[2] = nothing
    end
    if ex.head === :block || ex.head === :quote
        filter!(x -> !(x isa LineNumberNode), ex.args)
    end
    for arg in ex.args
        arg isa Expr && strip_linenums!(arg)
    end
    return ex
end

function truncate_width(str::String, maxwidth::Int)
    textwidth(str) <= maxwidth && return str
    width = 0
    for (i, c) in pairs(str)
        width += textwidth(c)
        if width > maxwidth - 1
            return string(str[1:prevind(str, i)], "…")
        end
    end
    return str
end
