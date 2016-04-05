# TimerOutputs

[![Build Status](https://travis-ci.org/KristofferC/TimerOutputs.jl.svg?branch=master)](https://travis-ci.org/KristofferC/TimerOutputs.jl)

`TimerOutputs` is a small Julia package that is used to generate formatted output from timings made in different sections of a program. It exports a macro `@timeit` that is similar to the `@time` macro in Base except you also give a label to the block you time. In the end of the program it is possible to print a nicely formatted table presenting how much time was spent in each section and how many calls were made.

This package is inspired by the `TimerOutput` class in [deal.ii](https://dealii.org/) which works in a similar way.

## Usage

The easiest way to show how the package work is with a simple example:

```julia
using TimerOutputs

# Create a TimerOutput, this is the main type that keeps track of everything.
const to = TimerOutput()

# Time a block of code with a label to the `TimerOutput` named "to"
# Multiple `TimerOutput`s are possible
@timeit to "sleep" sleep(0.2)

rands() = for i in 1:10^7 rand() end

# Returns the value on the right, like Base @time
rand_vals = @timeit to "randoms" rands()

# Time a multistatement block
b = @timeit to "multi statements" begin
    sleep(0.2)
    rands()
    5
end

# Call to a previously used label adds to that timer and call counter
@timeit to "sleep" sleep(0.3)
```

Printing `to` now gives a formatted table showing the number of calls, the total time spent in each section, and the percentage of the total time since `to` was created.


```
print(to)
+---------------------------------------------+------------+------------+
| Total wallclock time elapsed since start    |   2.548 s  |            |
|                                             |            |            |
| Section                         | no. calls |  wall time | % of total |
+---------------------------------------------+------------+------------+
| sleep                           |         2 | 502.747 ms |       20 % |
| multi statements                |         1 | 201.773 ms |      7.9 % |
| randoms                         |         1 |  19.267 ms |     0.76 % |
+---------------------------------------------+------------+------------+
```

## Reset

A `TimerOutput` can be reset by calling `reset!(to::TimerOutput)`. This removes all saved data and updates the creation time of the `TimerOutput` instance.

## Disable

By setting the variable `DISABLE_TIMING = true` in Julia **before** loading `TimerOutputs`, the `@timeit` macro is changed to just return the value it operates on.
