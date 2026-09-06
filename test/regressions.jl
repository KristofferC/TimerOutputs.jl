module RegressionTests

using TimerOutputs
using Test
using FlameGraphs

const TO = TimerOutputs

macro declare_local()
    return esc(:(local x::Int = 1))
end

function generated_declaration(to)
    return @timeit to "declaration" begin
        @declare_local
        x + 1
    end
end

module Debug
    using TimerOutputs
    const to = TimerOutput()
    @timeit_debug to function argument(inner)
        return inner + 1
    end
    const evaluations = Ref(0)
    target() = (evaluations[] += 1; "dynamic debug")
    call() = @timeit_debug target() identity(3)
end

@testset "macro hygiene and dynamic labels" begin
    reset_timer!()
    evaluations = Ref(0)
    label() = (evaluations[] += 1; "dynamic")
    @test (@timeit label() identity(2)) == 2
    @test evaluations[] == 1
    @test TO.DEFAULT_TIMER["dynamic"].ncalls == 1

    to = TimerOutput()
    target() = (evaluations[] += 1; to)
    @test (@timeit target() identity(3)) == 3
    @test evaluations[] == 2
    @test to["identity"].ncalls == 1
    @test (@timeit NoTimerOutput() identity(4)) == 4

    @test generated_declaration(to) == 2
    @test to["declaration"].ncalls == 1
    disable_timer!(to)
    @test generated_declaration(to) == 2
    @test to["declaration"].ncalls == 1
    @test generated_declaration(NoTimerOutput()) == 2

    @test Debug.argument(2) == 3
    @test Debug.call() == 3
    @test Debug.evaluations[] == 0
    TO.enable_debug_timings(Debug)
    @test Base.invokelatest(Debug.argument, 2) == 3
    @test Base.invokelatest(Debug.call) == 3
    @test Debug.evaluations[] == 1
    @test Debug.to["argument"].ncalls == 1
    @test TO.DEFAULT_TIMER["dynamic debug"].ncalls == 1
    TO.disable_debug_timings(Debug)
    reset_timer!()
end

exprnodes(ex) = ex isa Expr ? 1 + sum(exprnodes, ex.args; init = 0) : 1
function nested_expansion(depth)
    body = :(x += 1)
    for _ in 1:depth
        body = :(
            if flag
                $body
            end
        )
    end
    return macroexpand(@__MODULE__, :(@timeit_all to $body))
end

@timeit_all to function all_throw(to)
    error("expected")
end
const all_throw_line = @__LINE__() - 2

@testset "nested instrumentation grows linearly" begin
    @test exprnodes(nested_expansion(12)) < 4 * exprnodes(nested_expansion(6))
    body = nested_expansion(12)
    f = Core.eval(
        @__MODULE__, :(
            function nested(to, flag)
                x = 0
                $body
                return x
            end
        )
    )
    to = TimerOutput()
    @test Base.invokelatest(f, to, true) == 1
    @test Base.invokelatest(f, to, false) == 0
    @test isempty(to.stack)
    @test Base.invokelatest(f, NoTimerOutput(), true) == 1
    for timer in (TimerOutput(), NoTimerOutput())
        frames = try
            all_throw(timer)
        catch
            stacktrace(catch_backtrace())
        end
        @test any(frame -> frame.func === :all_throw && frame.line == all_throw_line, frames)
    end
end

@testset "user labels take precedence over complements" begin
    for fanout in (0, 8), user_first in (false, true)
        to = TimerOutput()
        @timeit to "outer" begin
            @timeit to "payload" identity(0)
            if user_first
                @timeit to "~outer~" identity(1)
            end
            for i in 1:fanout
                @timeit to string(i) identity(i)
            end
        end
        TO.complement!(to)
        @timeit to "outer" begin
            @timeit to "~outer~" begin
                @timeit to "user child" identity(2)
            end
        end
        TO.complement!(to)
        TO.complement!(to)
        section = to["outer", "~outer~"]
        @test !section.is_complement
        @test section.ncalls == 1 + user_first
        @test section["user child"].ncalls == 1
        @test length(collect(keys(to["outer"]))) == length(unique(keys(to["outer"])))
        exported = TO.todict(to)["inner_timers"]["outer"]["inner_timers"]["~outer~"]
        @test haskey(exported["inner_timers"], "user child")
    end
end

end # module
