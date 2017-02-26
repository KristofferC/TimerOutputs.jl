# TimerOutputs

[![Build Status](https://travis-ci.org/KristofferC/TimerOutputs.jl.svg?branch=master)](https://travis-ci.org/KristofferC/TimerOutputs.jl) [![codecov](https://codecov.io/gh/KristofferC/TimerOutputs.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/KristofferC/TimerOutputs.jl)

`TimerOutputs` is a small Julia package that is used to generate formatted output from timings made in different sections of a program.
It exports the macro `@timeit` that is similar to the `@time` macro in Base except one also assigns a label to the code section being timed.
It is then possible to print a nicely formatted table presenting how much time was spent in each section and how many calls were made.
Multiple calls to code sections with the same label will accumulate the time data for that label.

An example of the output is shown below:

```
+--------------------------------+-----------+--------+---------+
| Wall time elapsed since start  |    16.9 s |        |         |
|                                |           |        |         |
| Section              | n calls | wall time | % tot  | % timed |
+----------------------+---------+-----------+--------+---------+
| assemble             |       5 |    9.64 s |  57.1% |   61.5% |
| linear solve         |       4 |    4.85 s |  28.8% |     31% |
| create sparse mat... |       5 |   0.729 s |  4.32% |   4.65% |
| export               |       1 |   0.459 s |  2.72% |   2.93% |
+----------------------+---------+-----------+--------+---------+
```

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

# Time the function, @timeit returns the value being evaluated, just like Base @time
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

# do syntax for exception safe timings
function i_will_throw()
    time_section(to, "throwing") do
        sleep(0.5)
        throw(error("wups"))
        print("nope")
    end
end

i_will_throw()

# Call to a previously used label adds to that timer and call counter
for i in 1:100
    @timeit to "sleep" sleep(0.01)
end
```

Printing `to` now gives a formatted table showing the number of calls, the total time spent in each section, and the percentage of the time spent in each section since `to` was created as well as the percentage of the total time timed:

```julia
+--------------------------------+-----------+--------+---------+
| Wall time elapsed since start  |    6.72 s |        |         |
|                                |           |        |         |
| Section              | n calls | wall time | % tot  | % timed |
+----------------------+---------+-----------+--------+---------+
| sleep                |     101 |    1.34 s |  19.9% |   46.7% |
| throwing             |       1 |   0.502 s |  7.46% |   17.5% |
| test function        |       1 |   0.502 s |  7.46% |   17.5% |
| nested               |       1 |   0.502 s |  7.46% |   17.5% |
| randoms              |       1 |  0.0231 s | 0.343% |  0.804% |
+----------------------+---------+-----------+--------+---------+
```

## Resetting

It is possible to reset a timer by calling `reset_timer!(to::TimerOutput)`. This will remove all sections and reset the start of the timer to the current time:

```julia
julia> reset_timer!(to)
+--------------------------------+-----------+--------+---------+
| Wall time elapsed since start  |6.43e-05 s |        |         |
|                                |           |        |         |
| Section              | n calls | wall time | % tot  | % timed |
+----------------------+---------+-----------+--------+---------+
+----------------------+---------+-----------+--------+---------+
```

## Default Timer

It is often the case that one timer is enough. There is therefore a version of `@timeit` that does not take a `TimerOutput` instance.
This default timer is printed using `print_timer()`, reset using `reset_timer!()` and printed using `print_timer()`.
For example:

```julia
reset_timer!()

@timeit "section" sleep(0.2)
@timeit "section2" sleep(0.1)

print_timer()
```

which prints:
```
+--------------------------------+-----------+--------+---------+
| Wall time elapsed since start  |    1.17 s |        |         |
|                                |           |        |         |
| Section              | n calls | wall time | % tot  | % timed |
+----------------------+---------+-----------+--------+---------+
| section              |       1 |    0.23 s |  19.7% |   69.4% |
| section2             |       1 |   0.101 s |  8.66% |   30.6% |
+----------------------+---------+-----------+--------+---------+
```

Note that only the `@timeit` functionality is provided for the default timer. This means that it is not exception safe.


## Overhead

There is a small overhead in timing a section (~100 ns) which means that this package is not suitable for measuring sections that finish very quickly.
For proper benchmarking you want to use a more suitable tool like [*BenchmarkTools*](https://github.com/JuliaCI/BenchmarkTools.jl).

## Author

Kristoffer Carlsson - @KristofferC