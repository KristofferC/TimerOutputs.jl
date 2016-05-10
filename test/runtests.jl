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
reset_timer!(to)

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

# test throws

function foo2(v)
    @timeit to "throwing" begin
        sleep(1)
        print(v[6]) # OOB
    end
end

try
    foo2(rand(5))
catch e
    isa(e, BoundsError) || rethrow(e)
end

@test "throwing" in keys(sections(to))

@test_throws ArgumentError @timeit to 5 sleep(1)


function foo3()
    to = TimerOutput()

    to_tester = TimerOutput()
    @timeit to "runtime" for i in 1:10^6
        @timeit to_tester "test" 1+1
    end

    return to, to_tester
end

to3, to4 = foo3()

@test "runtime" in keys(sections(to3))
@test "test" in keys(sections(to4))

function foo4()
    to = TimerOutput()

    enter_section(to, "sec1")
    sleep(0.25)
    enter_section(to, "sec2")
    sleep(0.25)
    exit_section(to)

    exit_section(to, "sec1")

    return to
end

to5 = foo4()

@test "sec1" in keys(sections(to5))
@test "sec2" in keys(sections(to5))

print(to5)
