# TimerOutputs

[![Build Status](https://travis-ci.org/KristofferC/TimerOutputs.jl.svg?branch=master)](https://travis-ci.org/KristofferC/TimerOutputs.jl) [![codecov](https://codecov.io/gh/KristofferC/TimerOutputs.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/KristofferC/TimerOutputs.jl)

`TimerOutputs` is a small Julia package that is used to generate formatted output from timings made in different sections of a program. It exports the macro `@timeit` that is similar to the `@time` macro in Base except one also assigns a label to the code section being timed. It is then possible to print a nicely formatted table presenting how much time was spent in each section and how many calls were made. Multiple calls to code sections with the same label will accumulate the time data for that label.

This package is inspired by the `TimerOutput` class in [deal.ii](https://dealii.org/) which works in a similar way.

## Usage

The easiest way to show how the package work is with a few examples.

```julia
using TimerOutputs

# Create a TimerOutput, this is the main type that keeps track of everything.
# It is possible to have multiple `TimerOutputs()` simultaneously.
const to = TimerOutput()

# Time a section code with the label "sleep" to the `TimerOutput` named "to"
@timeit to "sleep" sleep(0.2)

# Create a function to later time
rands() = for i in 1:10^7 rand() end

# Time the function, @timeit returns the value on the right, just like Base @time
rand_vals = @timeit to "randoms" rands()

# Explicit enter and exiting sections:
function time_test()
    enter_section(to, "test function")
    sleep(0.5)
    exit_section(to)
end

time_test()

# "do"-syntax to support function that might throw or have mutliple return paths
function i_will_throw()
    time_section(to, "throwing") do
        sleep(0.5)
        throw(error("wups"))
        print("nope")
    end
end

i_will_throw()

# Time a multi statement block
b = @timeit to "multi statements" begin
    sleep(0.2)
    rands()
    5
end

# Call to a previously used label adds to that timer and call counter
@timeit to "sleep" sleep(0.3)
```

Printing `to` now gives a formatted table showing the number of calls, the total time spent in each section, and the percentage of the time spent in each section since `to` was created as well as the percentage of the total time timed:

```julia
julia> print(to)
+--------------------------------+-----------+--------+---------+
| Wall time elapsed since start  |    6.21 s |        |         |
|                                |           |        |         |
| Section              | n calls | wall time | % tot  | % timed |
+----------------------+---------+-----------+--------+---------+
| sleep                |       2 |   0.548 s |  8.82% |   30.7% |
| throwing             |       1 |   0.504 s |  8.12% |   28.2% |
| test function        |       1 |   0.502 s |  8.07% |   28.1% |
| multi statements     |       1 |   0.216 s |  3.48% |   12.1% |
| randoms              |       1 |  0.0162 s |  0.26% |  0.906% |
+----------------------+---------+-----------+--------+---------+
```

## Disable

By setting the variable `DISABLE_TIMING = true` in Julia **before** loading `TimerOutputs`, the `@timeit` macro is changed to do nothing. This is useful if one wants to avoid the (quite small) overhead of the timings without having to actually remove the macros from the code.

## Overhead

There is a small overhead in the timings which means that this package is not intended to measure sections that finish very quickly.
