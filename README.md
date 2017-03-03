# TimerOutputs

[![Build Status](https://travis-ci.org/KristofferC/TimerOutputs.jl.svg?branch=master)](https://travis-ci.org/KristofferC/TimerOutputs.jl) [![codecov](https://codecov.io/gh/KristofferC/TimerOutputs.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/KristofferC/TimerOutputs.jl)

`TimerOutputs` is a small Julia package that is used to generate formatted output from timings made in different sections of a program.
It's main functionality is the `@timeit` macro, similar to the `@time` macro in Base except one also assigns a label to the code section being timed.
Multiple calls to code sections with the same label (and in the same "scope") will accumulate the data for that label.
After the program has executed, it is possible to print a nicely formatted table presenting how much time, allocations and number of calls were made in each section.
The output can be customized as to only show the things you are interested in.

An example of the output (used in a finite element simulation) is shown below

```
 ─────────────────────────────────────────────────────────────────────────────
                                       Time                  Allocations       
                              ──────────────────────   ────────────────────────
       Tot / % measured:          17.6s / 93.7%            17.8GiB / 99.8%     

  Section             ncalls    time   %tot  %timed      alloc   %tot  %alloc 
 ─────────────────────────────────────────────────────────────────────────────
  assemble                 5    10.7s  61.0%  61.0%     15.8GiB  88.5%  88.5%
  linear solve             4    5.54s  31.5%  31.5%     1.54GiB  8.66%  8.66%
  create sparse ma...      5    734ms  4.18%  4.18%      512MiB  2.81%  2.81%
  export                   1    575ms  3.28%  3.28%     6.55MiB  0.04%  0.04%
 ─────────────────────────────────────────────────────────────────────────────
```

The first line presents the total (wall) time passed and allocations made since the start of the timer as well as the percentage of those totals that was spent inside timed sections.
The following lines shows data for all the timed sections. The section label is shown first followed by the number of calls made to that section. Then, the total time / allocations in that section, as well as percentage with respect to the total measured data (inside timed sections) and the total data since the timer was started is shown.

## Usage

The easiest way to show how the package work is with a few examples of timing sections.

```julia
using TimerOutputs

# Create a TimerOutput, this is the main type that keeps track of everything.
const to = TimerOutput()

# Time a section code with the label "sleep" to the `TimerOutput` named "to"
@timeit to "sleep" sleep(0.02)

# Create a function to later time
rands() = rand(10^7)

# Time the function, @timeit returns the value being evaluated, just like Base @time
rand_vals = @timeit to "randoms" rands();

# Nested sections:
function time_test()
    @timeit to "nest 1" begin
        sleep(0.1)
        @timeit to "level 2.1" sleep(0.1)
        @timeit to "level 2.2" sleep(0.1)
    end
    @timeit to "nest 2" begin
        @timeit to "level 2.1" sleep(0.1)
        @timeit to "level 2.2" sleep(0.1)
    end
end

time_test()

# a function version with `do` syntax for exception safety
function i_will_throw()
    timeit(to, "throwing") do
        sleep(0.5)
        throw(error("this is fine..."))
        print("nope")
    end
end

i_will_throw()

# Call to a previously used label accumulates data
for i in 1:100
    @timeit to "sleep" sleep(0.01)
end
```

Printing `to` shows a formatted table showing the number of calls, the total time spent in each section, and the percentage of the time spent in each section since `to` was created as well as the percentage of the total time timed. Similar information is available for allocations:

```
 ───────────────────────────────────────────────────────────────────────
                                 Time                  Allocations       
                        ──────────────────────   ────────────────────────
    Tot / % measured:       2.27s / 59.6%            76.4MiB / 97.0%     

  Section       ncalls    time   %tot  %timed      alloc   %tot  %alloc 
 ───────────────────────────────────────────────────────────────────────
  sleep            101    1.14s  50.2%  50.2%     38.0KiB  0.05%  0.05%
  throwing           1    502ms  22.1%  22.1%        384B  0.00%  0.00%
  nest 1             1    304ms  13.4%  13.4%     2.73KiB  0.00%  0.00%
    level 2.1        1    101ms  4.46%  4.46%        368B  0.00%  0.00%
    level 2.2        1    101ms  4.45%  4.45%        368B  0.00%  0.00%
  nest 2             1    202ms  8.91%  8.91%     2.38KiB  0.00%  0.00%
    level 2.1        1    101ms  4.46%  4.46%        368B  0.00%  0.00%
    level 2.2        1    101ms  4.46%  4.46%        368B  0.00%  0.00%
  randoms            1    124ms  5.47%  5.47%     76.3MiB  99.9%  99.9%
 ───────────────────────────────────────────────────────────────────────
```

## Settings for printing:

The `print_timer([io::IO = STDOUT], to::TimerOutput, kwargs)` takes a number of keyword arguments to change the output. They are listed here:

* `allocations::Bool` ─ show the allocation columns (default true)
* `sortby::Symbol` ─ sort the sections according to `:time` (default), `:ncalls`, `:allocations` or `:name`
* `linechars::Symbol` ─ use either `:unicode` (default) or `ascii` to draw the horizontal lines in the table
* `compact::Symbol` ─ remove the `%timed` and `%alloc` column since if all of the program is timed, these are equal to the `%tot` column, default `false`.

## Flattening

If sections are nested like in the example below:

```julia
to = TimerOutput()

@timeit to "nest 1" begin
    sleep(0.1)
    @timeit to "level 2.1" sleep(0.1)
    for i in 1:20; @timeit to "level 2.2" sleep(0.02); end
end
@timeit to "nest 2" begin
    for i in 1:30; @timeit to "level 2.1" sleep(0.01); end
    @timeit to "level 2.2" sleep(0.1)
end
```

the table is displayed as:

```julia
julia> show(to, compact = true, allocations = false)
 ──────────────────────────────────────
  Section       ncalls    time   %tot 
 ──────────────────────────────────────
  nest 1             1    625ms  59.0%
    level 2.2       20    423ms  39.9%
    level 2.1        1    101ms  9.54%
  nest 2             1    435ms  41.0%
    level 2.1       30    334ms  31.5%
    level 2.2        1    101ms  9.54%
 ──────────────────────────────────────
```

It is possible to flatten this timer using the `TimerOutputs.flatten` function that accumulates the data for all sections with identical labels:

```julia
julia> to_flatten = TimerOutputs.flatten(to);

julia> show(to_flatten; compact = true, allocations = false)
 ────────────────────────────────────
  Section     ncalls    time   %tot
 ────────────────────────────────────
  nest 1           1    670ms  60.6%
  level 2.2       21    525ms  47.4%
  nest 2           1    436ms  39.4%
  level 2.1       31    436ms  39.4%
 ────────────────────────────────────
```

## Resetting

A timer is reset by calling `reset_timer!(to::TimerOutput)`. This will remove all sections and reset the start of the timer to the current time / allocation values:

## Default Timer

It is often the case that it is enough to only use one timer. For convenience, there is therefore a version of all the functions and macros that does not take a `TimerOutput` instance and then uses a global timer defined created in the package.
Note that this global timer is shared among all users of the package.
For example:

```julia
reset_timer!()

@timeit "section" sleep(0.02)
@timeit "section2" sleep(0.1)

print_timer()
```

which prints:
```julia
julia> print_timer()
 ────────────────────────────────────────────────────────────────────
                              Time                  Allocations       
                     ──────────────────────   ────────────────────────
  Tot / % measured:      122ms / 17.5%            1.47KiB / 0.35%     

  Section    ncalls    time   %tot  %timed      alloc   %tot  %alloc 
 ────────────────────────────────────────────────────────────────────
  section2        1    101ms  82.7%  82.7%        464B  30.9%  30.9%
  section         1   21.1ms  17.3%  17.3%     1.02KiB  69.1%  69.1%
 ────────────────────────────────────────────────────────────────────
```

The default timer object can be retrieved with `TimerOutputs.get_defaultimer()`.

## Indexing into a table

Any `TimerOutput` can be indexed with a section string which returns a new `TimerOutput` with that section as the "root". For example:


```julia
to = TimerOutput()

@timeit to "nest 1" begin
    @timeit to "nest 2" begin
        @timeit to "nest 3.1" sleep(0.1)
        @timeit to "nest 3.2" sleep(0.1)
        @timeit to "nest 3.3" sleep(0.1)
    end
    sleep(0.3)
end
```

```julia
julia> show(to; compact = true, allocations = false, linechars = :ascii)
 ---------------------------------------
  Section        ncalls    time   %tot 
 ---------------------------------------
  nest 1              1    605ms   100%
    nest 2            1    304ms  50.2%
      nest 3.2        1    101ms  16.7%
      nest 3.1        1    101ms  16.7%
      nest 3.3        1    101ms  16.7%
 ---------------------------------------
julia> to_2 = to["nest 1"]["nest 2"];

julia> show(to_2; compact = true, allocations = false, linechars = :ascii)
 -----------------------------------
  Section    ncalls    time   %tot 
 -----------------------------------
  nest 3.2        1    101ms  33.3%
  nest 3.1        1    101ms  33.3%
  nest 3.3        1    101ms  33.3%
 -----------------------------------
```

The percentages showed are now relative to that "root".

## Querying data

The (unexported) functions `ncalls`, `time`, `allocated` gives the accumulated data for a sections. Time is given in nano seconds and allocations in bytes. For example (using the `to` object from above):

```julia
julia> TimerOutputs.ncalls(to["nest 1"])
1

julia> TimerOutputs.time(to["nest 1"])
350441733

julia> TimerOutputs.allocated(to["nest 1"])
1507698
```

## Overhead

There is a small overhead in timing a section (0.25 μs) which means that this package is not suitable for measuring sections that finish very quickly.
For proper benchmarking you want to use a more suitable tool like [*BenchmarkTools*](https://github.com/JuliaCI/BenchmarkTools.jl).

## Author

Kristoffer Carlsson - @KristofferC

## Acknowledgments

This package is inspired by the `TimerOutput` class in [deal.ii](https://dealii.org/).
