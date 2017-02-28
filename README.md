# TimerOutputs

[![Build Status](https://travis-ci.org/KristofferC/TimerOutputs.jl.svg?branch=master)](https://travis-ci.org/KristofferC/TimerOutputs.jl) [![codecov](https://codecov.io/gh/KristofferC/TimerOutputs.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/KristofferC/TimerOutputs.jl)

`TimerOutputs` is a small Julia package that is used to generate formatted output from timings made in different sections of a program.
It exports the macro `@timeit` that is similar to the `@time` macro in Base except one also assigns a label to the code section being timed.
It is then possible to print a nicely formatted table presenting how much time was spent in each section and how many calls were made.
Multiple calls to code sections with the same label will accumulate the time data for that label.

An example of the output is shown below:

```
 ══════════════════════════════════════════════════════════════════════════════
                                         Time                 Allocations      
                               ──────────────────────   ───────────────────────
  Total/percentage measured:        15.3 s / 93.7%          17.8GiB / 99.8%    
                                                                
  Section              ncalls    time   %tot  %timed      alloc   %tot  %alloc
 ──────────────────────────────────────────────────────────────────────────────
  assemble                  5   9.06 s  55.6%  59.4%     15.8GiB  88.4%  88.5%
  linear solve              4   4.81 s  29.6%  31.6%     1.54GiB  8.64%  8.65%
  create sparse mat...      5    850ms  5.22%  5.57%      512MiB  2.81%  2.81%
  export                    1    537ms  3.30%  3.52%     6.51MiB  0.04%  0.04%
 ══════════════════════════════════════════════════════════════════════════════
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

```
 ═════════════════════════════════════════════════════════════════════════════
                                         Time                 Allocations      
                               ──────────────────────   ──────────────────────
  Total/percentage measured:        2.87 s / 51.8%          1.00MiB / 2.34%    
                                                                
  Section              ncalls    time   %tot  %timed     alloc   %tot  %alloc
 ─────────────────────────────────────────────────────────────────────────────
  sleep                   101   1.34 s  24.2%  46.7%     795KiB  1.82%  77.6%
  throwing                  1    502ms  9.05%  17.5%     192  B  0.00%  0.02%
  test function             1    502ms  9.05%  17.5%     224  B  0.00%  0.02%
  nested                    1    502ms  9.05%  17.5%     176  B  0.00%  0.02%
  randoms                   1   24.3ms  0.44%  0.85%     229KiB  0.52%  22.3%
 ═════════════════════════════════════════════════════════════════════════════
```

## Resetting

It is possible to reset a timer by calling `reset_timer!(to::TimerOutput)`. This will remove all sections and reset the start of the timer to the current time:

```julia
julia> reset_timer!(to)
 ══════════════════════════════════════════════════════════════════════════════
                                         Time                 Allocations      
                               ──────────────────────   ───────────────────────
  Total/percentage measured:        0.00ns / 0.00%             0  B / 0.00%    
                                                                
  Section              ncalls    time   %tot  %timed      alloc   %tot  %alloc
 ──────────────────────────────────────────────────────────────────────────────
 ══════════════════════════════════════════════════════════════════════════════
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
 ══════════════════════════════════════════════════════════════════════════════
                                         Time                 Allocations      
                               ──────────────────────   ───────────────────────
  Total/percentage measured:         302ms / 60.9%           384  B / 0.01%    
                                                                
  Section              ncalls    time   %tot  %timed      alloc   %tot  %alloc
 ──────────────────────────────────────────────────────────────────────────────
  section                   1    201ms  40.5%  66.6%      192  B  0.01%  50.0%
  section2                  1    101ms  20.4%  33.4%      192  B  0.01%  50.0%
 ══════════════════════════════════════════════════════════════════════════════
```

Note that only the `@timeit` functionality is provided for the default timer.
This means that it is cannot be used in an exception safe way.


## Print settings

The section with allocation can be disabled from printing with `enable_allocations!(::Bool)`:

```julia
julia> to = TimerOutput();

julia> enable_allocations!(false)
false

julia> @timeit to "section" rand(10^8);

julia> to
 ════════════════════════════════════════════════════
                                         Time         
                               ──────────────────────
  Total/percentage measured:         614ms / 11.2%    
                                                                
  Section              ncalls    time   %tot  %timed
 ────────────────────────────────────────────────────
  section                   1    614ms  11.2%   100%
 ════════════════════════════════════════════════════
```

Sorting of the section can be done with `sortmode!(mode::Symbol)` where `mode` can be `:time` or `:allocated`.

The characters used to draw the horizaontal lines are changed with `linemode!(mode::Symbol)` where `mode` can be `:unicode` (default) or `:ascii`.
The ASCII version looks as:

```julia
julia> linemode!(:ascii)
:ascii

julia> to
 ====================================================
                                         Time         
                               ----------------------
  Total/percentage measured:         614ms / 0.34%    
                                                                
  Section              ncalls    time   %tot  %timed
 ----------------------------------------------------
  section                   1    614ms  0.34%   100%
 ====================================================
```


## Overhead

There is a small overhead in timing a section (~100 ns) which means that this package is not suitable for measuring sections that finish very quickly.
For proper benchmarking you want to use a more suitable tool like [*BenchmarkTools*](https://github.com/JuliaCI/BenchmarkTools.jl).

## Author

Kristoffer Carlsson - @KristofferC