using TimerOutputs
using Test

import TimerOutputs: DEFAULT_TIMER, ncalls, flatten,
                     prettytime, prettymemory, prettypercent, prettycount, todict

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
1+1
sleep(0.1)
end

@timeit "multi statement" begin
1+1
sleep(0.1)
end

@test "multi statement" in keys(to.inner_timers)
@test "multi statement" in keys(DEFAULT_TIMER.inner_timers)

@timeit to "sleep" sleep(0.1)
@timeit to "sleep" sleep(0.1)
@timeit to "sleep" sleep(0.1)

@timeit "sleep" sleep(0.1)
@timeit "sleep" sleep(0.1)
@timeit "sleep" sleep(0.1)

@test haskey(to, "sleep")
@test !haskey(to, "slep")
@test ncalls(to["sleep"]) == 4
@test ncalls(DEFAULT_TIMER["sleep"]) == 4


# Check reset works
reset_timer!(to)
reset_timer!()

@test length(keys(to.inner_timers)) == 0
@test length(keys(DEFAULT_TIMER.inner_timers)) == 0


# Check return values get propagated
function foo(a)
    a+a
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
@test ncalls(DEFAULT_TIMER["nest 1"])== 1
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
    for i in 1:10^7
        @timeit to "loop" 1+1
    end
end

many_loops()

a = 3
@timeit to "a$a"  1+1
@timeit "a$a" 1+1

@test "a3" in collect(keys(to.inner_timers))
@test "a3" in collect(keys(DEFAULT_TIMER.inner_timers))

reset_timer!(DEFAULT_TIMER)
toz = TimerOutput()
@timeit toz "foo" 1+1
reset_timer!(toz)
@timeit toz "foo" 1+1
@test "foo" in keys(toz.inner_timers)

tof = TimerOutput()
@timeit tof ff1(x) = x
@timeit tof ff2(x)::Float64 = x
@timeit tof function ff3(x) x end
@timeit tof function ff4(x)::Float64 x end

@timeit ff5(x) = x
@timeit ff6(x)::Float64 = x
@timeit function ff7(x) x end
@timeit function ff8(x)::Float64 x end

@timeit ff9(x::T) where {T} = x
@timeit (ff10(x::T)::Float64) where {T} = x
@timeit function ff11(x::T) where {T} x end
@timeit function ff12(x::T)::Float64 where {T} x end

@timeit "foo" ff13(x::T) where {T} = x
@timeit "bar" (ff14(x::T)::Float64) where {T} = x
@timeit "baz" function ff15(x::T) where {T} x end
@timeit "quz" function ff16(x::T)::Float64 where {T} x end

@timeit tof "foo" ff17(x::T) where {T} = x
@timeit tof "bar" (ff18(x::T)::Float64) where {T} = x
@timeit tof "baz" function ff19(x::T) where {T} x end
@timeit tof "quz" function ff20(x::T)::Float64 where {T} x end

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
for (t, str) in ((9999,    "10.0μs"), (99999,    " 100μs"),
                 (9999999, "10.0ms"), (99999999, " 100ms"))
    @test prettytime(t) == str
end
for (b, str) in ((9.999*1024,   "10.0KiB"), (99.999*1024,   " 100KiB"),
                 (9.999*1024^2, "10.0MiB"), (99.999*1024^2, " 100MiB"),
                 (9.999*1024^3, "10.0GiB"), (99.999*1024^3, " 100GiB"))
    @test prettymemory(b)   == str
end
for (num, den, str) in ((0.9999, 1, "100.0%"), (0.09999, 1, " 10.0%"))
    @test prettypercent(num, den) == str
end
for (t, str) in ((9.999*1024,   "10.0KiB"), (99.999*1024,   " 100KiB"),
                 (9.999*1024^2, "10.0MiB"), (99.999*1024^2, " 100MiB"),
                 (9.999*1024^3, "10.0GiB"), (99.999*1024^3, " 100GiB"))
    @test prettymemory(t)   == str
end
for (c, str) in ((9999, "10.0k"), (99999, "100k"),
                 (9999999, "10.0M"), (99999999, "100M"),
                 (9999999999, "10.0B"), (99999999999, "100B"))
    @test prettycount(c) == str
end

# `continue` inside a timeit section
to_continue = TimerOutput()
function continue_test()
   for i = 1:10
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
    ff1() = @timeit to "ff1" 1+1
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

    to_merged = merge(to1, to2, to3)
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

    table = sprint((io, to)->show(io, to, sortby = :firstexec), to)
    @test match(r"cccc", table).offset < match(r"bbbb", table).offset < match(r"aaaa", table).offset

    to = TimerOutput()
    @timeit to "group" begin
        @timeit to "aaaa" sleep(0.1)
        @timeit to "nested_group" begin sleep(0.1)
            @timeit to "bbbb" sleep(0.1)
            @timeit to "cccc" sleep(0.1)
        end
    end

    table = sprint((io, to)->show(io, to, sortby = :firstexec), to)
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
    s = x -> x+1
    t = to(s)
    t(1)
    ncalls(to.inner_timers[repr(s)]) == 1
end
