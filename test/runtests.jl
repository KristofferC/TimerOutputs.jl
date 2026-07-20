using TimerOutputs
using Test

import TimerOutputs: DEFAULT_TIMER, ncalls, flatten,
    prettytime, prettymemory, prettypercent, prettycount, todict,
    heatbar, heat_crayon

using FlameGraphs

reset_timer!()

# Timing from modules that don't import much
baremodule NoImports
    using TimerOutputs
    using Base: sleep
    @timeit "baresleep" sleep(0.1)
end

@testset "TimerOutput" begin

    @test "baresleep" in keys(DEFAULT_TIMER.inner_timers)

    to = TimerOutput()
    @timeit to "sleep" sleep(0.1)
    @timeit "sleep" sleep(0.1)

    @test "sleep" in keys(to.inner_timers)
    @test "sleep" in keys(DEFAULT_TIMER.inner_timers)

    @timeit to "multi statement" begin
        1 + 1
        sleep(0.1)
    end

    @timeit "multi statement" begin
        1 + 1
        sleep(0.1)
    end

    @test "multi statement" in keys(to.inner_timers)
    @test "multi statement" in keys(DEFAULT_TIMER.inner_timers)

    @timeit to "sleep" sleep(0.1)
    @timeit to "sleep" sleep(0.1)
    @timeit to "sleep" sleep(0.1)
    timeit(to, "sleep") do
        sleep(0.1)
    end
    section = begin_timed_section!(to, "sleep")
    sleep(0.1)
    end_timed_section!(to, section)

    @timeit "sleep" sleep(0.1)
    @timeit "sleep" sleep(0.1)
    @timeit "sleep" sleep(0.1)
    timeit("sleep") do
        sleep(0.1)
    end
    section = begin_timed_section!("sleep")
    sleep(0.1)
    end_timed_section!(section)

    @test haskey(to, "sleep")
    @test !haskey(to, "slep")
    @test ncalls(to["sleep"]) == 6
    @test ncalls(DEFAULT_TIMER["sleep"]) == 6


    # Check reset works
    reset_timer!(to)
    reset_timer!()

    @test length(keys(to.inner_timers)) == 0
    @test length(keys(DEFAULT_TIMER.inner_timers)) == 0


    # Check return values get propagated
    function foo(a)
        a + a
    end

    to2 = TimerOutput()

    a = @timeit to2 "foo" foo(5)
    b = @timeit "foo" foo(5)

    @test a === 10
    @test b === 10
    @test "foo" in collect(keys(to2.inner_timers))
    @test "foo" in collect(keys(DEFAULT_TIMER.inner_timers))

    # Test nested
    c = @timeit to2 "nest 1" begin
        sleep(0.01)
        @timeit to2 "nest 2" sleep(0.02)
        @timeit to2 "nest 2" sleep(0.02)
        5
    end

    d = @timeit "nest 1" begin
        sleep(0.01)
        @timeit "nest 2" sleep(0.02)
        @timeit "nest 2" sleep(0.02)
        5
    end

    @test ncalls(to2["nest 1"]) == 1
    @test ncalls(to2["nest 1"]["nest 2"]) == 2
    @test ncalls(DEFAULT_TIMER["nest 1"]) == 1
    @test ncalls(DEFAULT_TIMER["nest 1"]["nest 2"]) == 2
    @test c === 5
    @test d == 5

    # test throws
    function foo2(v)
        @timeit to "throwing" begin
            sleep(0.01)
            print(v[6]) # OOB
        end
    end

    function foo3(v)
        @timeit "throwing" begin
            sleep(0.01)
            print(v[6]) # OOB
        end
    end

    try
        foo2(rand(5))
    catch e
        isa(e, BoundsError) || rethrow(e)
    end

    try
        foo3(rand(5))
    catch e
        isa(e, BoundsError) || rethrow(e)
    end

    @test "throwing" in keys(to.inner_timers)
    @test "throwing" in keys(DEFAULT_TIMER.inner_timers)

    reset_timer!(to)

    @timeit to "foo" begin
        sleep(0.05)
        @timeit to "bar" begin
            @timeit to "foo" sleep(0.05)
            @timeit to "foo" sleep(0.05)
            @timeit to "baz" sleep(0.05)
            @timeit to "bar" sleep(0.05)
        end
        @timeit to "bur" sleep(0.025)
    end
    @timeit to "bur" sleep(0.025)

    tom = flatten(to)
    @test ncalls(tom["foo"]) == 3
    @test ncalls(tom["bar"]) == 2
    @test ncalls(tom["bur"]) == 2
    @test ncalls(tom["baz"]) == 1

    function many_loops()
        for i in 1:(10^7)
            @timeit to "loop" 1 + 1
        end
    end

    many_loops()

    a = 3
    @timeit to "a$a"  1 + 1
    @timeit "a$a" 1 + 1

    @test "a3" in collect(keys(to.inner_timers))
    @test "a3" in collect(keys(DEFAULT_TIMER.inner_timers))

    reset_timer!(DEFAULT_TIMER)
    toz = TimerOutput()
    @timeit toz "foo" 1 + 1
    reset_timer!(toz)
    @timeit toz "foo" 1 + 1
    @test "foo" in keys(toz.inner_timers)

    tof = TimerOutput()
    @timeit tof ff1(x) = x
    @timeit tof ff2(x)::Float64 = x
    @timeit tof function ff3(x)
        x
    end
    @timeit tof function ff4(x)::Float64
        x
    end

    @timeit ff5(x) = x
    @timeit ff6(x)::Float64 = x
    @timeit function ff7(x)
        x
    end
    @timeit function ff8(x)::Float64
        x
    end

    @timeit ff9(x::T) where {T} = x
    @timeit (ff10(x::T)::Float64) where {T} = x
    @timeit function ff11(x::T) where {T}
        x
    end
    @timeit function ff12(x::T)::Float64 where {T}
        x
    end

    @timeit "foo" ff13(x::T) where {T} = x
    @timeit "bar" (ff14(x::T)::Float64) where {T} = x
    @timeit "baz" function ff15(x::T) where {T}
        x
    end
    @timeit "quz" function ff16(x::T)::Float64 where {T}
        x
    end

    @timeit tof "foo" ff17(x::T) where {T} = x
    @timeit tof "bar" (ff18(x::T)::Float64) where {T} = x
    @timeit tof "baz" function ff19(x::T) where {T}
        x
    end
    @timeit tof "quz" function ff20(x::T)::Float64 where {T}
        x
    end

    for i in 1:2
        @test ff1(1) === 1
        @test ff2(1) === 1.0
        @test ff3(1) === 1
        @test ff4(1) === 1.0
        @test ff5(1) === 1
        @test ff6(1) === 1.0
        @test ff7(1) === 1
        @test ff8(1) === 1.0
        @test ff9(1) === 1
        @test ff10(1) === 1.0
        @test ff11(1) === 1
        @test ff12(1) === 1.0
        @test ff13(1) === 1
        @test ff14(1) === 1.0
        @test ff15(1) === 1
        @test ff16(1) === 1.0
        @test ff17(1) === 1
        @test ff18(1) === 1.0
        @test ff19(1) === 1
        @test ff20(1) === 1.0
    end

    @test ncalls(tof["ff1"]) == 2
    @test ncalls(tof["ff2"]) == 2
    @test ncalls(tof["ff3"]) == 2
    @test ncalls(tof["ff4"]) == 2
    @test ncalls(tof["foo"]) == 2
    @test ncalls(tof["bar"]) == 2
    @test ncalls(tof["baz"]) == 2
    @test ncalls(tof["quz"]) == 2

    @test ncalls(DEFAULT_TIMER["ff5"]) == 2
    @test ncalls(DEFAULT_TIMER["ff6"]) == 2
    @test ncalls(DEFAULT_TIMER["ff7"]) == 2
    @test ncalls(DEFAULT_TIMER["ff8"]) == 2
    @test ncalls(DEFAULT_TIMER["ff9"]) == 2
    @test ncalls(DEFAULT_TIMER["ff10"]) == 2
    @test ncalls(DEFAULT_TIMER["ff11"]) == 2
    @test ncalls(DEFAULT_TIMER["ff12"]) == 2
    @test ncalls(DEFAULT_TIMER["foo"]) == 2
    @test ncalls(DEFAULT_TIMER["bar"]) == 2
    @test ncalls(DEFAULT_TIMER["baz"]) == 2
    @test ncalls(DEFAULT_TIMER["quz"]) == 2

    function foo()
        reset_timer!()
        @timeit "asdf" bar()
    end

    bar() = print_timer()

    foo()

    io = IOBuffer()
    show(io, to)
    show(io, to; allocations = false)
    show(io, to; allocations = false, compact = true)
    show(io, to; sortby = :ncalls)
    show(io, to; sortby = :time)
    show(io, to; sortby = :allocations)
    show(io, to; sortby = :name)
    show(io, to; sortby = :firstexec)
    show(io, to; linechars = :ascii)
    show(io, to; title = "A short title")
    show(io, to; title = "A very long title that will be truncated")

    # issue 22: edge cases for rounding
    for (t, str) in (
            (9999, "10.0μs"), (99999, " 100μs"),
            (9999999, "10.0ms"), (99999999, " 100ms"),
        )
        @test prettytime(t) == str
    end
    for (b, str) in (
            (9.999 * 1024, "10.0KiB"), (99.999 * 1024, " 100KiB"),
            (9.999 * 1024^2, "10.0MiB"), (99.999 * 1024^2, " 100MiB"),
            (9.999 * 1024^3, "10.0GiB"), (99.999 * 1024^3, " 100GiB"),
        )
        @test prettymemory(b) == str
    end
    for (num, den, str) in ((0.9999, 1, "100.0%"), (0.09999, 1, " 10.0%"))
        @test prettypercent(num, den) == str
    end
    for (t, str) in (
            (9.999 * 1024, "10.0KiB"), (99.999 * 1024, " 100KiB"),
            (9.999 * 1024^2, "10.0MiB"), (99.999 * 1024^2, " 100MiB"),
            (9.999 * 1024^3, "10.0GiB"), (99.999 * 1024^3, " 100GiB"),
        )
        @test prettymemory(t) == str
    end
    for (c, str) in (
            (9999, "10.0k"), (99999, "100k"),
            (9999999, "10.0M"), (99999999, "100M"),
            (9999999999, "10.0B"), (99999999999, "100B"),
        )
        @test prettycount(c) == str
    end

    # `continue` inside a timeit section
    to_continue = TimerOutput()
    function continue_test()
        for i in 1:10
            @timeit to_continue "x" @timeit to_continue "test" begin
                continue
            end
        end
    end
    continue_test()
    @test isempty(to_continue.inner_timers["x"].inner_timers["test"].inner_timers)


    # Test @timeit_debug
    to_debug = TimerOutput()
    function debug_test()
        @timeit_debug to_debug "sleep" sleep(0.001)
    end

    TimerOutputs.disable_debug_timings(@__MODULE__)
    debug_test()
    @test !("sleep" in keys(to_debug.inner_timers))
    TimerOutputs.enable_debug_timings(@__MODULE__)
    debug_test()
    @test "sleep" in keys(to_debug.inner_timers)


    # Test functional-form @timeit_debug with @eval'ed functions
    to_debug = TimerOutput()

    @timeit_debug to_debug function baz(x, y)
        @timeit_debug to_debug "sleep" sleep(0.001)
        return x + y * x
    end

    TimerOutputs.disable_debug_timings(@__MODULE__)
    baz(1, 2.0)
    @test isempty(to_debug.inner_timers)

    TimerOutputs.enable_debug_timings(@__MODULE__)
    baz(1, 2.0)
    @test "baz" in keys(to_debug.inner_timers)
    @test "sleep" in keys(to_debug.inner_timers["baz"].inner_timers)
    TimerOutputs.disable_debug_timings(@__MODULE__)

    to = TimerOutput()
    @timeit to "section1" sleep(0.02)
    @timeit to "section2" begin
        @timeit to "section2.1" sleep(0.1)
        sleep(0.01)
    end
    TimerOutputs.complement!(to)

    tom = flatten(to)
    @test ncalls(tom["~section2~"]) == 1

    # Repeated calls refresh complement sections instead of creating duplicate
    # labels (which would make indexing and serialization disagree).
    TimerOutputs.complement!(to)
    @test collect(keys(to["section2"])) == ["section2.1", "~section2~"]
    @test TimerOutputs.time(to["section2", "~section2~"]) ==
        todict(to)["inner_timers"]["section2"]["inner_timers"]["~section2~"]["time_ns"]

end # testset

struct Simulation
    timer::TimerOutput
    # state
end

@testset "Timer from argument" begin
    get_timer(sim) = sim.timer
    @timeit get_timer(sim) function step!(sim::Simulation)
        # important computation
    end
    sim = Simulation(TimerOutputs.TimerOutput())
    step!(sim)
    @test TimerOutputs.ncalls(sim.timer["step!"]) == 1
    step!(sim)
    @test TimerOutputs.ncalls(sim.timer["step!"]) == 2

    @timeit get_timer(args...; kw...) step2!(args...; kw...) = nothing
    step2!(sim)
    @test TimerOutputs.ncalls(sim.timer["step!"]) == 2
    @test TimerOutputs.ncalls(sim.timer["step2!"]) == 1
    step2!(sim)
    @test TimerOutputs.ncalls(sim.timer["step2!"]) == 2
end

# default timer without explicitly loading TimerOutputs
TimerOutputs.reset_timer!()
module TestModule
    using TimerOutputs: @timeit
    foo(x) = x
    @timeit "foo" foo(1)
end
@test "foo" in keys(DEFAULT_TIMER.inner_timers)
TimerOutputs.reset_timer!()

# Test sharing timers between modules
@test !haskey(TimerOutputs._timers, "TestModule2")
@test !haskey(TimerOutputs._timers, "my_timer")

to = get_timer("my_timer")
@timeit to "foo" sleep(0.1)
@test ncalls(get_timer("my_timer")["foo"]) == 1

module TestModule2
    using TimerOutputs: @timeit, get_timer
    foo(x) = x
    @timeit get_timer("TestModule2") "foo" foo(1)
    @timeit get_timer("my_timer") "foo" foo(1)
end

# Timer from module is accessible to root
@test haskey(TimerOutputs._timers, "TestModule2")
@test ncalls(get_timer("TestModule2")["foo"]) == 1
# Timer from root is accessible to module
@test ncalls(get_timer("my_timer")["foo"]) == 2

# Broken
#=
# Type inference with @timeit_debug
@timeit_debug function make_zeros()
   dims = (3, 4)
   zeros(dims)
end
@inferred make_zeros()
TimerOutputs.enable_debug_timings(@__MODULE__)
@inferred make_zeros()
=#

to = TimerOutput()
@timeit_debug to function f(x)
    g(x) = 2x
    g(x)
end
@test f(3) == 6
TimerOutputs.enable_debug_timings(@__MODULE__)
@test f(3) == 6
TimerOutputs.disable_debug_timings(@__MODULE__)

@testset "Not too many allocations #59" begin
    function doit(timer, n)
        ret = 0
        for i in 1:n
            @timeit timer "depth0" begin
                @timeit timer "depth1" begin
                    @timeit timer "depth2" begin
                        ret += sin(i)
                    end
                    @timeit timer "depth2b" begin
                        ret += cos(i)
                    end
                end
                @timeit timer "depth1b" begin

                end
            end
        end
        ret
    end

    to = TimerOutput()
    doit(to, 1)
    a0 = TimerOutputs.allocated(to["depth0"])
    a1 = TimerOutputs.allocated(to["depth0"]["depth1"])
    a2 = TimerOutputs.allocated(to["depth0"]["depth1"]["depth2"])

    to = TimerOutput()
    doit(to, 100000)

    to0 = to["depth0"]
    to1 = to0["depth1"]
    to1b = to0["depth1b"]
    to2 = to1["depth2"]
    to2b = to1["depth2b"]

    # test that leaf timers add zero allocations
    # and other timers only add allocations once
    @test TimerOutputs.allocated(to0) == a0
    @test TimerOutputs.allocated(to1) == a1
    @test TimerOutputs.allocated(to2) == a2
    @test TimerOutputs.allocated(to1b) == 0
    @test TimerOutputs.allocated(to2) == 0
    @test TimerOutputs.allocated(to2b) == 0
end

@testset "disable enable" begin
    to = TimerOutput()
    ff1() = @timeit to "ff1" 1 + 1
    ff1()
    @test ncalls(to["ff1"]) == 1
    disable_timer!(to)
    ff1()
    @test ncalls(to["ff1"]) == 1
    enable_timer!(to)
    ff1()
    @test ncalls(to["ff1"]) == 2
    @notimeit to ff1()
    ff1()
    @test ncalls(to["ff1"]) == 3

    # Restore the exact prior state even if the body changes it.
    disable_timer!(to)
    @test (@notimeit to enable_timer!(to)) == true
    @test !TimerOutputs.isenabled(to)

    # the functional form respects the disabled state like the macro does
    to2 = TimerOutput()
    disable_timer!(to2)
    @test timeit(() -> 42, to2, "recorded") == 42
    @test !haskey(to2, "recorded")
    enable_timer!(to2)
    @test timeit(() -> 42, to2, "kept") == 42
    @test haskey(to2, "kept")
end

# Type inference with @timeit_debug
@timeit_debug function make_zeros()
    dims = (3, 4)
    zeros(dims)
end
@inferred make_zeros()
TimerOutputs.enable_debug_timings(@__MODULE__)
@inferred make_zeros()

@testset "merge" begin
    to1 = TimerOutput()
    to2 = TimerOutput()
    to3 = TimerOutput()

    @timeit to1 "foo" identity(nothing)
    @timeit to1 "baz" identity(nothing)
    @timeit to1 "foobar" begin
        @timeit to1 "foo" identity(nothing)
        @timeit to1 "baz" identity(nothing)
    end

    @timeit to1 "bar" identity(nothing)
    @timeit to2 "baz" identity(nothing)
    @timeit to2 "foobar" begin
        @timeit to2 "bar" identity(nothing)
        @timeit to2 "baz" identity(nothing)
    end

    @timeit to3 "bar" identity(nothing)

    @test_throws MethodError merge()

    to_merged = merge(to1, to2, to3)
    @test to_merged !== to1
    merge!(to1, to2, to3)

    for to in [to1, to_merged]
        @test "foo" in collect(keys(to.inner_timers))
        @test "bar" in collect(keys(to.inner_timers))
        @test "foobar" in collect(keys(to.inner_timers))

        subto = to["foobar"]
        @test "foo" in collect(keys(subto.inner_timers))
        @test "bar" in collect(keys(subto.inner_timers))

        @test ncalls(to["foo"]) == 1
        @test ncalls(to["bar"]) == 2
        @test ncalls(to["baz"]) == 2

        @test ncalls(subto["foo"]) == 1
        @test ncalls(subto["bar"]) == 1
        @test ncalls(subto["baz"]) == 2
    end

    # a plain merge derives its total from the merged children (no override)
    @test to_merged.measured === nothing

    # merging a flattened timer must keep the original total, not the sum of
    # the flattened rows (which double-counts nested measurements)
    tof = TimerOutput()
    @timeit tof "outer" begin
        @timeit tof "inner" begin
            @timeit tof "leaf" identity(nothing)
        end
    end
    flat = flatten(tof)
    @test TimerOutputs.tottime(flat) == TimerOutputs.tottime(tof)
    @test TimerOutputs.totallocated(flat) == TimerOutputs.totallocated(tof)
    m = merge(flat)
    @test TimerOutputs.tottime(m) == TimerOutputs.tottime(flat)
    @test TimerOutputs.totallocated(m) == TimerOutputs.totallocated(flat)
    # merging two flattened timers sums their (original) totals
    m2 = merge(flat, flat)
    @test TimerOutputs.tottime(m2) == 2 * TimerOutputs.tottime(flat)
end

# Issue #118
let to = TimerOutput()
    @timeit to "foo" identity(nothing)
    @timeit to "foobar" begin
        @timeit to "foo" identity(nothing)
        @timeit to "baz" identity(nothing)
    end
    @timeit to "baz" identity(nothing)

    @test ncalls(to.inner_timers["foo"]) == 1
    @test ncalls(to.inner_timers["foobar"]) == 1
    @test ncalls(to.inner_timers["foobar"].inner_timers["foo"]) == 1
    @test ncalls(to.inner_timers["foobar"].inner_timers["baz"]) == 1
    @test ncalls(to.inner_timers["baz"]) == 1
end

@testset "sortby firstexec" begin
    to = TimerOutput()
    @timeit to "cccc" sleep(0.1)
    @timeit to "cccc" sleep(0.1)
    @timeit to "bbbb" sleep(0.1)
    @timeit to "aaaa" sleep(0.1)
    @timeit to "cccc" sleep(0.1)

    table = sprint((io, to) -> show(io, to, sortby = :firstexec), to)
    @test match(r"cccc", table).offset < match(r"bbbb", table).offset < match(r"aaaa", table).offset

    to = TimerOutput()
    @timeit to "group" begin
        @timeit to "aaaa" sleep(0.1)
        @timeit to "nested_group" begin
            sleep(0.1)
            @timeit to "bbbb" sleep(0.1)
            @timeit to "cccc" sleep(0.1)
        end
    end

    table = sprint((io, to) -> show(io, to, sortby = :firstexec), to)
    @test match(r"aaaa", table).offset < match(r"bbbb", table).offset < match(r"cccc", table).offset
end

@static if isdefined(Threads, Symbol("@spawn"))
    @testset "merge at custom points during multithreading" begin
        to = TimerOutput()
        @timeit to "1" begin
            @timeit to "1.1" sleep(0.1)
            @timeit to "1.2" sleep(0.1)
            @timeit to "1.3" sleep(0.1)
        end

        @sync begin
            @timeit to "2" Threads.@spawn begin
                to2 = TimerOutput()
                @timeit to2 "2.1" sleep(0.1)
                @timeit to2 "2.2" sleep(0.1)
                @timeit to2 "2.3" sleep(0.1)
                merge!(to, to2, tree_point = ["2"])
            end

            @timeit to "3" Threads.@spawn begin
                to3 = TimerOutput()
                @sync begin
                    @timeit to3 "3.1" Threads.@spawn begin
                        to31 = TimerOutput()
                        @timeit to31 "3.1.1" sleep(0.1)
                        @timeit to31 "3.1.2" sleep(0.1)
                        @timeit to31 "3.1.3" sleep(0.1)
                        merge!(to3, to31, tree_point = ["3.1"])
                    end
                    @timeit to3 "3.2" Threads.@spawn begin
                        to32 = TimerOutput()
                        @timeit to32 "3.2.1" sleep(0.1)
                        @timeit to32 "3.2.2" sleep(0.1)
                        @timeit to32 "3.2.3" sleep(0.1)
                        merge!(to3, to32, tree_point = ["3.2"])
                    end
                end
                merge!(to, to3, tree_point = ["3"])
            end
        end

        @test "1" in collect(keys(to.inner_timers))
        @test ncalls(to.inner_timers["1"]) == 1
        @test "2" in collect(keys(to.inner_timers))
        @test ncalls(to.inner_timers["2"]) == 1
        @test "3" in collect(keys(to.inner_timers))
        @test ncalls(to.inner_timers["3"]) == 1
        @test !in("1.1", collect(keys(to.inner_timers)))
        @test !in("2.1", collect(keys(to.inner_timers)))
        @test !in("3.1", collect(keys(to.inner_timers)))
        @test !in("3.1.1", collect(keys(to.inner_timers)))
        @test !in("3.2", collect(keys(to.inner_timers)))
        @test !in("3.2.1", collect(keys(to.inner_timers)))

        to1 = to.inner_timers["1"]
        @test "1.1" in collect(keys(to1.inner_timers))
        @test ncalls(to1.inner_timers["1.1"]) == 1

        to2 = to.inner_timers["2"]
        @test "2.1" in collect(keys(to2.inner_timers))
        @test ncalls(to2.inner_timers["2.1"]) == 1
        @test !in("3.1", collect(keys(to2.inner_timers)))

        to3 = to.inner_timers["3"]
        @test "3.1" in collect(keys(to3.inner_timers))
        @test ncalls(to3.inner_timers["3.1"]) == 1
        @test "3.2" in collect(keys(to3.inner_timers))
        @test ncalls(to3.inner_timers["3.2"]) == 1
        @test !in("2.1", collect(keys(to3.inner_timers)))

        to31 = to3.inner_timers["3.1"]
        @test "3.1.1" in collect(keys(to31.inner_timers))
        @test ncalls(to31.inner_timers["3.1.1"]) == 1
        @test !in("3.2.1", collect(keys(to31.inner_timers)))

        to32 = to3.inner_timers["3.2"]
        @test "3.2.1" in collect(keys(to32.inner_timers))
        @test ncalls(to32.inner_timers["3.2.1"]) == 1
        @test !in("3.1.1", collect(keys(to32.inner_timers)))
    end
end

@testset "Serialization" begin
    # Setup a timer
    to = TimerOutput()
    @timeit to "foo" identity(nothing)
    @timeit to "foobar" begin
        @timeit to "foo" identity(nothing)
        @timeit to "baz" identity(nothing)
    end
    @timeit to "baz" identity(nothing)


    function compare(to, d)
        @test TimerOutputs.tottime(to) == d["total_time_ns"]
        @test TimerOutputs.ncalls(to) == d["n_calls"]
        @test TimerOutputs.totallocated(to) == d["total_allocated_bytes"]
        @test TimerOutputs.allocated(to) == d["allocated_bytes"]
        @test TimerOutputs.time(to) == d["time_ns"]
        for ((k1, timer), (k2, obj)) in zip(to.inner_timers, d["inner_timers"])
            @test k1 == k2
            compare(timer, obj)
        end
    end

    compare(to, todict(to))
end

# functions instrumented in different modules that share a name
module InstrModA
    dup(x) = x + 1
end
module InstrModB
    dup(x) = x + 1
end

@testset "InstrumentedFunctions" begin
    to = TimerOutput()
    f = to(x -> x^2, "f")
    @test isempty(to.inner_timers)
    f(1)
    @test ncalls(to.inner_timers["f"]) == 1
    h = to(x -> f(x) + 1, "h")
    h(1)
    @test ncalls(to.inner_timers["h"]) == 1
    @test ncalls(to.inner_timers["h"].inner_timers["f"]) == 1
    s = x -> x + 1
    t = to(s)
    t(1)
    @test ncalls(to.inner_timers[repr(s)]) == 1
end

@testset "InstrumentedFunctions labels" begin
    # the section key is the module-qualified name, but it prints as the bare name
    to = TimerOutput()
    to(InstrModA.dup)(1)
    @test haskey(to.inner_timers, "Main.InstrModA.dup")
    out = sprint(show, to)
    @test occursin("dup", out)
    @test !occursin("InstrModA", out)

    # two functions with the same bare name keep their qualified labels
    to = TimerOutput()
    to(InstrModA.dup)(1)
    to(InstrModB.dup)(1)
    @test haskey(to.inner_timers, "Main.InstrModA.dup")
    @test haskey(to.inner_timers, "Main.InstrModB.dup")
    out = sprint(show, to)
    @test occursin("InstrModA.dup", out)
    @test occursin("InstrModB.dup", out)

    # an explicit name is shown verbatim, never shortened
    to = TimerOutput()
    to(InstrModA.dup, "A.dup")(1)
    @test occursin("A.dup", sprint(show, to))
end

@testset "Interleaved sections" begin
    to = TimerOutput()
    section1 = begin_timed_section!(to, "1")
    sleep(0.1)
    section2 = begin_timed_section!(to, "2")
    sleep(0.1)
    end_timed_section!(to, section1)
    sleep(0.1)
    end_timed_section!(to, section2)
end

@testset "@timeit works with an empty label" begin
    to = TimerOutput()
    @timeit to "" begin end
    @test ncalls(to.inner_timers[""]) == 1
end

@testset "FlameGraphsExt" begin
    to = TimerOutput()
    begin
        func() = @timeit to "func" sleep(0.1)
        @timeit to "foo 1" begin
            sleep(0.1)
            @timeit to "bar" begin
                sleep(0.1)
                @timeit to "baz" begin
                    sleep(0.1)
                    func()
                end
            end
        end
        @timeit to "foo 2" begin
            sleep(0.1)
            @timeit to "bar" begin
                sleep(0.1)
                @timeit to "baz" begin
                    sleep(0.1)
                    func()
                end
            end
        end
    end
    flamegraph(to)
    flamegraph(to, crop_root = true)

    # cropping an empty timer must not throw (no children to crop to)
    @test flamegraph(TimerOutput(); crop_root = true) !== nothing
    @test flamegraph(TimerOutput()) !== nothing
end

function foo_77(::Float64) end

@testset "Stacktraces (#77)" begin
    err = try
        @timeit "foo_77" foo_77(1)
    catch e
        sprint(Base.display_error, e, catch_backtrace())
    end

    @test err isa AbstractString

    # this err shouldn't have any stacktrace pointing into TimerOutputs.jl
    @test !contains(err, "src/TimerOutput.jl:")
end

@timeit "foo_168" function foo_168()
    1 + 1

    error("boom")
end
const foo_168_error_line = @__LINE__() - 2

@timeit_debug "dbg_168" function dbg_168()
    1 + 1

    error("boom")
end
const dbg_168_error_line = @__LINE__() - 2

@testset "function body keeps line numbers (#168)" begin
    st = try
        foo_168()
    catch
        stacktrace(catch_backtrace())
    end
    i = findfirst(f -> f.func === :foo_168, st)
    @test st[i].line == foo_168_error_line
    @test endswith(String(st[i].file), "runtests.jl")

    # debug variant: the user body lives in the `inner` closure, but the error
    # line must still be visible in the trace
    st = try
        dbg_168()
    catch
        stacktrace(catch_backtrace())
    end
    @test any(f -> f.line == dbg_168_error_line && endswith(String(f.file), "runtests.jl"), st)
end

@testset "reset_timer! inside a timed section (#172)" begin
    to = TimerOutput()
    @timeit to function foo_172(x)
        reset_timer!(to)
        x
    end
    @test foo_172(42) == 42

    # nested sections unwinding after a reset must not throw either
    @timeit to "outer" begin
        @timeit to "inner" reset_timer!(to)
    end
    @timeit to "afterwards" 1 + 1
    @test ncalls(to["afterwards"]) == 1
end

@testset "no NaN for zero-call sections" begin
    @test prettytime(NaN) == "     -"
    to = TimerOutput()
    begin_timed_section!(to, "unfinished")
    str = sprint(show, to)
    @test !occursin("NaN", str)
end

@testset "macro edge cases" begin
    to = TimerOutput()
    x = 7
    # non-Expr bodies (literals, symbols) work
    @test (@timeit to "lit" 42) == 42
    @test (@timeit to "sym" x) == 7
    @test (@timeit to "nothing" nothing) === nothing
    @test ncalls(to["lit"]) == 1
    # invalid forms give the friendly usage error
    @test_throws ArgumentError macroexpand(@__MODULE__, :(@timeit 42))
    @test_throws ArgumentError macroexpand(@__MODULE__, :(@timeit))
    # a call body with no derivable label (operator, indexing) still errors
    @test_throws ArgumentError macroexpand(@__MODULE__, :(@timeit a + b))
    @test_throws ArgumentError macroexpand(@__MODULE__, :(@timeit a[i]))
    # an empty timer still renders
    @test sprint(show, TimerOutput()) isa String
end

@testset "call shorthand (#159)" begin
    g(x) = x + 1

    # 1-arg: default timer, label derived from the callee
    reset_timer!()
    @test (@timeit g(41)) == 42
    @test ncalls(DEFAULT_TIMER["g"]) == 1

    # 2-arg: explicit timer, label derived from the callee
    to = TimerOutput()
    @test (@timeit to g(41)) == 42
    @test ncalls(to["g"]) == 1

    # qualified calls keep the qualification in the label
    @test (@timeit to Base.identity(3)) == 3
    @test ncalls(to["Base.identity"]) == 1

    # an explicit (literal or interpolated) label is never treated as a timer
    i = 2
    @timeit to "lit" g(0)
    @timeit to "iter_$i" g(0)
    @test ncalls(to["lit"]) == 1 && ncalls(to["iter_2"]) == 1

    # composes with the zero-overhead NoTimerOutput
    nt = NoTimerOutput()
    @test (@timeit nt g(41)) == 42
end

@testset "ascii output is pure ASCII (#115)" begin
    to = TimerOutput()
    @timeit to "microsleep" @timeit to "nested" 1 + 1
    to["microsleep"].time = 5_000 # 5 μs
    str = sprint((io, x) -> show(io, x; linechars = :ascii), to)
    @test isascii(str)
    @test occursin("us", str)
    # ascii mode uses plain indentation, not tree guide characters
    @test occursin("\n   nested", str)
    str_unicode = sprint(show, to)
    @test occursin("μs", str_unicode)
    @test occursin("└─ nested", str_unicode)
end

@testset "compact without allocations hides the header block" begin
    to = TimerOutput()
    @timeit to "a" 1 + 1
    str = sprint((io, x) -> show(io, x; compact = true, allocations = false), to)
    @test !occursin("Time", str)
    @test !occursin("Tot / % measured", str)
    # but compact with allocations keeps it
    str2 = sprint((io, x) -> show(io, x; compact = true), to)
    @test occursin("Time", str2) && occursin("Tot / % measured", str2)
end

@testset "table is cropped to the display width (#166)" begin
    to = TimerOutput()
    @timeit to "a section with an annoyingly long name that overflows" 1 + 1
    ctx = IOContext(IOBuffer(), :limit => true, :displaysize => (24, 60))
    str = sprint(io -> show(IOContext(io, ctx), to))
    @test all(l -> textwidth(l) <= 60, split(str, "\n"))
    # the Section column is shrunk before any data columns are cropped
    @test occursin("…", str)
    @test occursin("ncalls", str) && occursin("time", str)
end

@testset "NoTimerOutput (#109)" begin
    nt = NoTimerOutput()
    f_nt(t) = @timeit t "sec" (1 + 1)
    @test f_nt(nt) == 2
    # compiles away entirely when the timer type is known (code coverage
    # inserts extra statements and inhibits inlining, so only check without).
    # Julia 1.10 leaves a benign `nothing` placeholder for the elided timer
    # binding, so count the statements that actually do something and check no
    # try/finally scaffolding survives.
    if Base.JLOptions().code_coverage == 0
        code = code_typed(f_nt, Tuple{NoTimerOutput})[1].first.code
        @test count(s -> s !== nothing, code) == 1
        @test !any(s -> s isa Expr && s.head === :enter, code)
    end
    @test (@allocated f_nt(nt)) == 0
    @test timeit(() -> 42, nt, "x") == 42
    section = begin_timed_section!(nt, "x")
    end_timed_section!(nt, section)
    @test (@notimeit nt f_nt(nt)) == 2
    @test !TimerOutputs.isenabled(nt)
    @test enable_timer!(nt) == false
    @test disable_timer!(nt) == false
    @test reset_timer!(nt) === nt
    # funcdef form
    @timeit nt nt_func(x) = x + 1
    @test nt_func(1) == 2
end

@testset "%par column (#192)" begin
    to = TimerOutput()
    @timeit to "outer" begin
        @timeit to "inner" 1 + 1
    end
    # opt-in via the columns keyword, not shown by default
    str = sprint((io, x) -> show(io, x; columns = [:ncalls, :time, :time_pct, :time_par]), to)
    @test occursin("%par", str)
    @test !occursin("%par", sprint(show, to))
end

@testset "maxdepth (#122)" begin
    to = TimerOutput()
    @timeit to "l1" @timeit to "l2" @timeit to "l3" 1 + 1
    str1 = sprint((io, x) -> show(io, x; maxdepth = 1), to)
    @test occursin("l1", str1) && !occursin("l2", str1)
    str2 = sprint((io, x) -> show(io, x; maxdepth = 2), to)
    @test occursin("l2", str2) && !occursin("l3", str2)
    @test occursin("l3", sprint(show, to))
    @test_throws ArgumentError sprint((io, x) -> show(io, x; maxdepth = 0), to)
end

@testset "columns selection" begin
    to = TimerOutput()
    @timeit to "a" @timeit to "b" 1 + 1
    header_line(s) = first(filter(l -> occursin("Section", l), split(s, "\n")))
    render(; kwargs...) = sprint((io, x) -> show(io, x; kwargs...), to)

    str = render(; columns = [:ncalls, :time])
    @test occursin("ncalls", str) && occursin("time", str)
    @test !occursin("avg", str) && !occursin("alloc", str) && !occursin("%tot", str)

    # order is respected, and group headers follow the columns
    str2 = render(; columns = [:time, :ncalls])
    @test findfirst("time", header_line(str2))[1] < findfirst("ncalls", header_line(str2))[1]
    str3 = render(; columns = [:allocs, :allocs_pct, :time])
    @test findfirst("Allocations", str3)[1] < findfirst("Time", str3)[1]

    # the compact/allocations keywords are shorthands for column selections
    # (token comparison: the header block presence may change column padding)
    @test split(header_line(render(; compact = true, allocations = false))) ==
        split(header_line(render(; columns = [:ncalls, :time, :time_pct])))
    @test split(header_line(render())) ==
        split(
        header_line(
            render(;
                columns = [
                    :ncalls, :time, :time_pct, :time_avg, :time_bar,
                    :spacer, :allocs, :allocs_pct, :allocs_avg, :allocs_bar,
                ]
            )
        )
    )

    @test_throws ArgumentError render(; columns = [:bogus])
end

@testset "GC time column (#173)" begin
    to = TimerOutput()
    @timeit to "gc" begin
        acc = Any[]
        for _ in 1:200
            push!(acc, rand(10_000))
        end
        GC.gc()
    end
    @timeit to "cheap" 1 + 1

    header_line(s) = first(filter(l -> occursin("Section", l), split(s, "\n")))

    # off by default, opt in with gc = true or the :gc_time column
    @test !occursin("GC", header_line(sprint(show, to)))
    @test occursin("GC", header_line(sprint((io, x) -> show(io, x; gc = true), to)))
    @test occursin("GC", header_line(sprint((io, x) -> show(io, x; columns = [:time, :gc_time]), to)))

    # a section that forced a collection records nonzero GC time
    @test TimerOutputs.gctime(to["gc"]) > 0
    @test TimerOutputs.gctime(to) == TimerOutputs.gctime(to.root)
    @test TimerOutputs.gctime(to["cheap"]) == 0

    # zero GC time renders as a null glyph, not "0.00ns" (a "-" in ascii mode)
    @test strip(TimerOutputs.prettygc(0, false)) == "∅"
    @test strip(TimerOutputs.prettygc(0, true)) == "-"
    @test strip(TimerOutputs.prettygc(1500, false)) == "1.50μs"
    gcstr = sprint((io, x) -> show(io, x; gc = true), to)
    @test occursin("∅", gcstr) && !occursin("0.00ns", gcstr)

    # merge sums GC time by section
    to2 = TimerOutput()
    @timeit to2 "gc" GC.gc()
    m = merge(to, to2)
    @test TimerOutputs.gctime(m["gc"]) == TimerOutputs.gctime(to["gc"]) + TimerOutputs.gctime(to2["gc"])

    # exposed through the serialization dict
    @test todict(to)["inner_timers"]["gc"]["gc_time_ns"] == TimerOutputs.gctime(to["gc"])
end

@testset "heat bar columns" begin
    # bar rendering: eighth-block resolution, empty remainder
    @test heatbar(0.0, false) == " "^8
    @test heatbar(0.5, false) == "████    "
    @test heatbar(1 / 16, false) == "▌       "
    @test heatbar(1.0, false) == "█"^8
    @test heatbar(2.0, false) == "█"^8 # clamped
    @test heatbar(0.5, false; width = 4) == "██  "
    # ascii mode keeps a track to show the extent in colorless logs
    @test heatbar(0.5, true) == "####...."

    # color ramp: cold -> blue, middle band -> default, hot -> red
    @test heat_crayon(0.0) == TimerOutputs.Crayon(foreground = (59, 76, 192))
    @test heat_crayon(1.0) == TimerOutputs.Crayon(foreground = (200, 10, 30))
    @test heat_crayon(0.2) == TimerOutputs.Crayon() # sqrt(0.2) ≈ 0.45 is inside the uncolored band

    to = TimerOutput()
    @timeit to "a" @timeit to "b" 1 + 1

    # bars are in the default columns, dropped by compact or bars = false
    str = sprint(show, to)
    @test occursin("█", str)
    @test !occursin("█", sprint((io, x) -> show(io, x; compact = true), to))
    nobars = sprint((io, x) -> show(io, x; bars = false), to)
    @test !occursin("█", nobars) && occursin("avg", nobars)
    # the bar glyphs render but no escape codes are emitted without color
    @test !occursin("\e[", str)
    # with color the bar cells get a truecolor foreground
    cstr = sprint(show, to; context = :color => true)
    @test occursin("\e[38;2;", cstr)

    # opt-in through the columns keyword
    sel = sprint((io, x) -> show(io, x; columns = [:ncalls, :time, :time_bar]), to)
    @test occursin("█", sel) && !occursin("alloc", sel)

    # a displayed subsection is its own 100% reference: full bar
    @test occursin("█"^8, sprint(show, to["a"]))

    # complement rows stay gray, never heat colored
    ccstr = sprint((io, x) -> show(io, x; complement = true), to; context = :color => true)
    for line in split(ccstr, '\n')
        occursin('~', line) && @test occursin("\e[90m", line)
    end
end

@testset "totals row styling" begin
    to = TimerOutput()
    @timeit to "a" 1 + 1
    cstr = sprint(show, to; context = :color => true)
    # PrettyTables styles merged label rows gray + underlined by default;
    # the totals row must stay plain
    @test !occursin("\e[4m", cstr)
    total_line = first(filter(l -> occursin("Tot / % measured", l), split(cstr, "\n")))
    @test !occursin("\e[90m", total_line)
end

@testset "complement display option" begin
    to = TimerOutput()
    @timeit to "outer" begin
        @timeit to "inner" sleep(0.01)
        sleep(0.01)
    end
    str = sprint((io, x) -> show(io, x; complement = true), to)
    @test occursin("~untimed~", str)
    @test occursin("~outer~", str)
    @test !occursin("~", sprint(show, to)) # off by default
    # display only: the timer itself is not mutated
    @test collect(keys(to)) == ["outer"]
    @test collect(keys(to["outer"])) == ["inner"]
    # complement rows are gray when the io supports color
    # Crayons checks terminal/global color support rather than IOContext(:color).
    cstr = withenv("FORCE_COLOR" => "true") do
        sprint((io, x) -> show(io, x; complement = true), to; context = :color => true)
    end
    @test occursin("\e[90m", cstr)
    @test !occursin("\e[90m ~", sprint((io, x) -> show(io, x; complement = true), to)) # no color, no ansi
    # works for a bare section too
    @test occursin("~outer~", sprint((io, x) -> show(io, x; complement = true), to["outer"]))
end

@testset "complement! keeps user sections named ~name~" begin
    # a section a user literally named `~outer~` holds real data and must not
    # be mistaken for a generated complement and deleted
    to = TimerOutput()
    @timeit to "outer" begin
        @timeit to "~outer~" begin
            @timeit to "payload" identity(nothing)
        end
    end
    TimerOutputs.complement!(to)
    @test haskey(to["outer"], "~outer~")
    @test haskey(to["outer", "~outer~"], "payload")
    @test ncalls(to["outer", "~outer~", "payload"]) == 1
    # repeated calls refresh generated complements without losing user data
    TimerOutputs.complement!(to)
    @test ncalls(to["outer", "~outer~", "payload"]) == 1
end

@testset "compact show in containers" begin
    to = TimerOutput()
    @timeit to "a" @timeit to "b" 1 + 1
    # the REPL displays container elements with a :compact IOContext
    display_str(x) = sprint(show, MIME("text/plain"), x)
    str = display_str([to, to])
    @test occursin("TimerOutput(\"root\", 1 section)", str)
    @test !occursin("ncalls", str) # no table headers inside the array
    @test occursin("Section(\"b\"", display_str([to["a", "b"]]))
    # top level printing is unaffected
    @test occursin("ncalls", sprint(show, to))
end

@testset "Tables.jl interface" begin
    import Tables
    to = TimerOutput()
    @timeit to "outer" begin
        @timeit to "inner" sleep(0.01)
    end
    @timeit to "second" 1 + 1
    @test Tables.istable(typeof(to))
    rows = Tables.rows(to)
    @test length(rows) == 3
    @test [r.path for r in rows] == ["outer", "outer/inner", "second"]
    @test [r.section for r in rows] == ["outer", "inner", "second"]
    @test [r.depth for r in rows] == [0, 1, 0]
    @test all(r.ncalls == 1 for r in rows)
    @test rows[2].time_ns >= 10^7
    cols = Tables.columntable(to)
    @test cols.ncalls == [1, 1, 1]
    @test Tables.schema(to).names ==
        (:path, :section, :depth, :ncalls, :time_ns, :gc_time_ns, :allocated_bytes, :firstexec_ns)

    # a bare section includes itself as the first row
    @test [r.path for r in Tables.rows(to["outer"])] == ["outer", "outer/inner"]
end

@testset "new API (0.6)" begin
    to = TimerOutput()
    @timeit to "a" @timeit to "b" 1 + 1
    # nested indexing and keys
    @test ncalls(to["a", "b"]) == 1
    @test collect(keys(to)) == ["a"]
    @test collect(keys(to["a"])) == ["b"]
    # sections print as tables
    str = sprint(show, to["a"])
    @test occursin("a", str)
    @test occursin("b", str)
    leaf_str = sprint(show, to["a", "b"])
    @test occursin("b", leaf_str)
    @test occursin("1", leaf_str)
    # pre-0.6 internal names still readable
    @test to.inner_timers["a"].accumulated_data.ncalls == 1
    # metrics are stored inline in the section; old accumulated_data name still reads
    @test to["a"].accumulated_data.ncalls == 1
    # copy is fully detached
    c = copy(to)
    c["a"].ncalls = 99
    @test ncalls(to["a"]) == 1
end

@timeit_all function timeit_all_thrower(n)
    x = 0

    error("boom")
end
const timeit_all_error_line = @__LINE__() - 2

@testset "@timeit_all" begin
    # every statement gets a `file:line: code` section, nested per block
    to = TimerOutput()
    @timeit_all to function timeit_all_sum(n)
        x = 0
        for i in 1:n
            x += i
        end
        x
    end
    @test timeit_all_sum(3) == 6
    func_section = to["timeit_all_sum"]
    filename = basename(@__FILE__)
    @test all(startswith(k, filename * ":") for k in keys(func_section))
    for_keys = filter(k -> occursin("for i = 1:n", k), collect(keys(func_section)))
    @test length(for_keys) == 1
    @test any(occursin("x += i", k) for k in keys(func_section[for_keys[1]]))

    # printing shows the file once, on the function row; statement rows below
    # shorten to `L<line>: code`
    out = sprint(show, to)
    @test occursin("timeit_all_sum @ " * filename, out)
    @test occursin(r"L\d+: x = 0", out)
    @test count(filename, out) == 1
    # a statement section shown directly keeps its full label
    @test occursin(filename * ":", sprint(show, func_section[for_keys[1]]))

    # control flow: early return, break, continue
    to = TimerOutput()
    @timeit_all to function taf_flow(n)
        s = 0
        for i in 1:n
            i == 2 && continue
            s += i
            if i > 3
                break
            end
        end
        if s > 100
            return 0
        elseif s < 0
            return -1
        end
        while true
            break
        end
        return s
    end
    @test taf_flow(10) == 1 + 3 + 4
    @test ncalls(to["taf_flow"]) == 1

    # nested function definitions get their own timer
    to = TimerOutput()
    @timeit_all to function taf_outer(n)
        function taf_helper(y)
            return y + 1
        end
        taf_helper(n)
    end
    @test taf_outer(1) == 2
    @test haskey(flatten(to), "taf_helper")

    # let / try / catch / finally
    to = TimerOutput()
    @timeit_all to function taf_scopes(n)
        y = let a = n
            a * 2
        end
        z = try
            error("x")
        catch
            y + 1
        finally
            nothing
        end
        return z
    end
    @test taf_scopes(3) == 7

    # type inference is preserved
    @timeit_all to function taf_stable(n)
        x = 0.0
        for i in 1:n
            x += i
        end
        x
    end
    taf_stable(2)
    @test (@inferred taf_stable(2)) == 3.0

    # block forms, with and without label
    to = TimerOutput()
    val = @timeit_all to "labeled" begin
        block_a = 1 + 1
        block_a + 1
    end
    @test val == 3
    @test haskey(to, "labeled")
    @test occursin("labeled @ " * filename, sprint(show, to))
    val = @timeit_all to begin
        block_b = 2 + 2
        block_b
    end
    @test val == 4

    # long statements get truncated labels
    to = TimerOutput()
    @timeit_all to "long" begin
        block_c = 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1
    end
    @test all(textwidth(k) <= 60 for k in keys(to["long"]))

    # @notimeit statements are not instrumented
    to = TimerOutput()
    @timeit_all to "skip" begin
        block_d = 1
        @notimeit to sleep(0.001)
    end
    @test !any(occursin("sleep", k) for k in keys(to["skip"]))

    # line numbers of the original code are preserved in stacktraces
    st = try
        timeit_all_thrower(1)
    catch
        stacktrace(catch_backtrace())
    end
    @test any(f -> f.line == timeit_all_error_line && endswith(String(f.file), "runtests.jl"), st)
end

include("test_coverage.jl")
