using TimerOutputs
using Test

import TimerOutputs: DEFAULT_TIMER, ncalls, flatten,
                     prettytime, prettymemory, prettypercent, prettycount

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


toz = TimerOutput()
@timeit toz "foo" 1+1
reset_timer!(toz)
@timeit toz "foo" 1+1
@test "foo" in keys(toz.inner_timers)

@timeit to ff1(x) = x
@timeit to ff2(x)::Float64 = x
@timeit to function ff3(x) x end
@timeit to function ff4(x)::Float64 x end

@timeit ff5(x) = x
@timeit ff6(x)::Float64 = x
@timeit function ff7(x) x end
@timeit function ff8(x)::Float64 x end

@timeit ff9(x::T) where {T} = x
@timeit (ff10(x::T)::Float64) where {T} = x
@timeit function ff11(x::T) where {T} x end
@timeit function ff12(x::T)::Float64 where {T} x end

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
end

@test ncalls(to["ff1"]) == 2
@test ncalls(to["ff2"]) == 2
@test ncalls(to["ff3"]) == 2
@test ncalls(to["ff4"]) == 2

@test ncalls(DEFAULT_TIMER["ff5"]) == 2
@test ncalls(DEFAULT_TIMER["ff6"]) == 2
@test ncalls(DEFAULT_TIMER["ff7"]) == 2
@test ncalls(DEFAULT_TIMER["ff8"]) == 2
@test ncalls(DEFAULT_TIMER["ff9"]) == 2
@test ncalls(DEFAULT_TIMER["ff10"]) == 2
@test ncalls(DEFAULT_TIMER["ff11"]) == 2
@test ncalls(DEFAULT_TIMER["ff12"]) == 2

@test "a3" in collect(keys(to.inner_timers))
@test "a3" in collect(keys(DEFAULT_TIMER.inner_timers))

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
for (num, den, str) in ((0.9999, 1, "100%"), (0.09999, 1, "10.0%"))
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

TimerOutputs.disable_debug_timings(Main)
debug_test()
@test !("sleep" in keys(to_debug.inner_timers))
TimerOutputs.enable_debug_timings(Main)
debug_test()
@test "sleep" in keys(to_debug.inner_timers)


# Test functional-form @timeit_debug with @eval'ed functions
to_debug = TimerOutput()

@timeit_debug to_debug function baz(x, y)
    @timeit_debug to_debug "sleep" sleep(0.001)
    return x + y * x
end

TimerOutputs.disable_debug_timings(Main)
baz(1, 2.0)
@test isempty(to_debug.inner_timers)

TimerOutputs.enable_debug_timings(Main)
baz(1, 2.0)
@test "baz" in keys(to_debug.inner_timers)
@test "sleep" in keys(to_debug.inner_timers["baz"].inner_timers)

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
