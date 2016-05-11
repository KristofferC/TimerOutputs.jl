# TimerOutputs

[![Build Status](https://travis-ci.org/KristofferC/TimerOutputs.jl.svg?branch=master)](https://travis-ci.org/KristofferC/TimerOutputs.jl) [![codecov](https://codecov.io/gh/KristofferC/TimerOutputs.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/KristofferC/TimerOutputs.jl)

`TimerOutputs` is a small Julia package that is used to generate formatted output from timings made in different sections of a program. It exports the macro `@timeit` that is similar to the `@time` macro in Base except one also assigns a label to the code section being timed. It is then possible to print a nicely formatted table presenting how much time was spent in each section and how many calls were made. Multiple calls to code sections with the same label will accumulate the time data for that label.

This package is inspired by the `TimerOutput` class in [deal.ii](https://dealii.org/) which works in a similar way.

## Usage

The easiest way to show how the package work is with a few examples of different way of timing sections.

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
    enter_section(to, "nested")
    sleep(0.5)
    exit_section(to) # Using the last entered section by default
    exit_section(to, "test function") # Can also be given explicitly 
end

time_test()

# @timeit is exception safe
function i_will_throw()
    @timeit to "throwing" begin
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
for i in 1:100
    @timeit to "sleep" sleep(0.01)
end
```

Printing `to` now gives a formatted table showing the number of calls, the total time spent in each section, and the percentage of the time spent in each section since `to` was created as well as the percentage of the total time timed:

```julia
julia> print(to)
+--------------------------------+-----------+--------+---------+
| Wall time elapsed since start  |    4.05 s |        |         |
|                                |           |        |         |
| Section              | n calls | wall time | % tot  | % timed |
+----------------------+---------+-----------+--------+---------+
| sleep                |     101 |    1.31 s |  32.4% |     43% |
| throwing             |       1 |   0.502 s |  12.4% |   16.4% |
| test function        |       1 |   0.501 s |  12.4% |   16.4% |
| nested               |       1 |   0.501 s |  12.4% |   16.4% |
| multi statements     |       1 |   0.218 s |  5.37% |   7.13% |
| randoms              |       1 |  0.0178 s | 0.439% |  0.583% |
+----------------------+---------+-----------+--------+---------+
```

## Resetting

It is possible to reset a timer by calling `reset_timer!(to::TimerOutput)`. This will remove all sections and reset the start of the timer to the current time:

```jl
julia> reset_timer!(to)
+--------------------------------+-----------+--------+---------+
| Wall time elapsed since start  |6.43e-05 s |        |         |
|                                |           |        |         |
| Section              | n calls | wall time | % tot  | % timed |
+----------------------+---------+-----------+--------+---------+
+----------------------+---------+-----------+--------+---------+
```

## Disable

By setting the variable `DISABLE_TIMING = true` in Julia **before** loading `TimerOutputs`, the `@timeit` macro is changed to do nothing. This is useful if one wants to avoid the overhead of the timings without having to actually remove the macros from the code.

## Overhead

There is a small overhead in the timings (a `try catch` for exception safety and a dictionary lookup for the label) which means that this package is not suitable to measure sections that finish very quickly.
