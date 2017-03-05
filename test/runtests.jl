using TimerOutputs
using Base.Test

import TimerOutputs: DEFAULT_TIMER, ncalls, flatten

reset_timer!()

@testset "TimerOutput" begin

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
    timeit(to, "throwing") do
        sleep(1)
        print(v[6]) # OOB
    end
end

function foo3(v)
    timeit("throwing") do
        sleep(1)
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
@test ncalls(tom["foo"])== 3
@test ncalls(tom["bar"]) == 2
@test ncalls(tom["bur"]) == 2
@test ncalls(tom["baz"]) == 1

function many_loops()
    for i in 1:10^7
        @timeit to "loop" 1+1
    end
end

many_loops()

io = IOBuffer()
show(io, to)
show(io, to; allocations = false)
show(io, to; allocations = false, compact = true)
show(io, to; sortby = :ncalls)
show(io, to; sortby = :time)
show(io, to; sortby = :allocations)
show(io, to; sortby = :name)
show(io, to; linechars = :ascii)
end # testset


