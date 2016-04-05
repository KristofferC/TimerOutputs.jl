using TimerOutputs
using Base.Test

import TimerOutputs: sections, ncalls

to = TimerOutput()

@timeit to "sleep" sleep(0.1)

@test "sleep" in keys(sections(to))

@timeit to "multi statement" begin
1+1
sleep(0.1)
end

@test "multi statement" in keys(sections(to))

@timeit to "sleep" sleep(0.1)
@timeit to "sleep" sleep(0.1)
@timeit to "sleep" sleep(0.1)

@test ncalls(sections(to)["sleep"]) == 4

# Check reset works
reset!(to)

@test length(keys(sections(to))) == 0


# Check return values get propagated
function foo(a)
    a+a
end

to2 = TimerOutput()

a = @timeit to2 "foo" foo(5)

@test a === 10
@test "foo" in keys(sections(to2))

# Test nested
c = @timeit to2 "nest 1" begin
    sleep(0.1)
    @timeit to2 "nest 2" sleep(0.2)
    @timeit to2 "nest 1" sleep(0.2)
    5
end

@test ncalls(sections(to2)["nest 1"]) == 2
@test ncalls(sections(to2)["nest 2"]) == 1
@test c === 5
