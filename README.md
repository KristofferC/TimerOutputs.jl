# TimerOutputs

[![Build Status](https://travis-ci.org/KristofferC/TimerOutputs.jl.svg?branch=master)](https://travis-ci.org/KristofferC/TimerOutputs.jl) [![codecov](https://codecov.io/gh/KristofferC/TimerOutputs.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/KristofferC/TimerOutputs.jl)

`TimerOutputs` is a small Julia package that is used to generate formatted output from timings made in different sections of a program.
It's main functionality is the `@timeit` macro, similar to the `@time` macro in Base except one also assigns a label to the code section being timed.
Multiple calls to code sections with the same label (and in the same "scope") will accumulate the data for that label.
After the program has executed, it is possible to print a nicely formatted table presenting how much time, allocations and number of calls were made in each section.
The output can be customized as to only show the things you are interested in.

If you find this package useful please give it a star. I like stars and it also helps me know where my development time is best spent.

## Example output

An example of the output (used in a finite element simulation) is shown below

```
 ───────────────────────────────────────────────────────────────────────────────
                                        Time                   Allocations
                                ──────────────────────   ───────────────────────
        Tot / % measured:            6.89s / 97.8%           5.20GiB / 85.0%

 Section                ncalls     time   %tot     avg     alloc   %tot      avg
 ───────────────────────────────────────────────────────────────────────────────
 assemble                    6    3.27s  48.6%   545ms   3.65GiB  82.7%   624MiB
   inner assemble         240k    1.92s  28.4%  7.98μs   3.14GiB  71.1%  13.7KiB
 linear solve                5    2.73s  40.5%   546ms    108MiB  2.39%  21.6MiB
 create sparse matrix        6    658ms  9.77%   110ms    662MiB  14.6%   110MiB
 export                      1   78.4ms  1.16%  78.4ms   13.1MiB  0.29%  13.1MiB
 ───────────────────────────────────────────────────────────────────────────────
```

The first line shows the total (wall) time passed and allocations made since the start of the timer as well as
the percentage of those totals spent inside timed sections.
The following lines shows data for all the timed sections.
The section label is shown first followed by the number of calls made to that section.
Finally, the total time elapsed or allocations made in that section are shown together with the
percentage of the total in that section and the average (time / allocations per call).

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

# Nested sections (sections with same name are not accumulated
# if they have different parents)
function time_test()
    @timeit to "nest 1" begin
        sleep(0.1)
        # 3 calls to the same label
        @timeit to "level 2.1" sleep(0.03)
        @timeit to "level 2.1" sleep(0.03)
        @timeit to "level 2.1" sleep(0.03)
        @timeit to "level 2.2" sleep(0.2)
    end
    @timeit to "nest 2" begin
        @timeit to "level 2.1" sleep(0.3)
        @timeit to "level 2.2" sleep(0.4)
    end
end

time_test()

# exception safe
function i_will_throw()
    @timeit to "throwing" do
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

# Can also annotate function definitions
@timeit to funcdef(x) = x

funcdef(2)
```

Printing `to` shows a formatted table showing the number of calls,
the total time spent in each section, and the percentage of the time
spent in each section since `to` was created as well as averages (per call).
Similar information is available for allocations:

```
 ──────────────────────────────────────────────────────────────────────
                               Time                   Allocations
                       ──────────────────────   ───────────────────────
   Tot / % measured:        5.09s / 56.0%            106MiB / 74.6%

 Section       ncalls     time   %tot     avg     alloc   %tot      avg
 ──────────────────────────────────────────────────────────────────────
 sleep            101    1.17s  41.2%  11.6ms   1.48MiB  1.88%  15.0KiB
 nest 2             1    703ms  24.6%   703ms   2.38KiB  0.00%  2.38KiB
   level 2.2        1    402ms  14.1%   402ms      368B  0.00%   368.0B
   level 2.1        1    301ms  10.6%   301ms      368B  0.00%   368.0B
 throwing           1    502ms  17.6%   502ms      384B  0.00%   384.0B
 nest 1             1    396ms  13.9%   396ms   5.11KiB  0.01%  5.11KiB
   level 2.2        1    201ms  7.06%   201ms      368B  0.00%   368.0B
   level 2.1        3   93.5ms  3.28%  31.2ms   1.08KiB  0.00%   368.0B
 randoms            1   77.5ms  2.72%  77.5ms   77.3MiB  98.1%  77.3MiB
 funcdef            1   2.66μs  0.00%  2.66μs         -  0.00%        -
 ──────────────────────────────────────────────────────────────────────
```

## Settings for printing:

The `print_timer([io::IO = stdout], to::TimerOutput, kwargs)`, (or `show`) takes a number of keyword arguments to change the output. They are listed here:

* `title::String` ─ title for the timer
* `allocations::Bool` ─ show the allocation columns (default `true`)
* `sortby::Symbol` ─ sort the sections according to `:time` (default), `:ncalls`, `:allocations` or `:name`
* `linechars::Symbol` ─ use either `:unicode` (default) or `:ascii` to draw the horizontal lines in the table
* `compact::Bool` ─ hide the `avg` column (default `false`)

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
julia> show(to, allocations = false, compact = true)
 ────────────────────────────────────
 Section       ncalls     time   %tot
 ────────────────────────────────────
 nest 1             1    669ms  60.5%
   level 2.2       20    423ms  38.3%
   level 2.1        1    101ms  9.15%
 nest 2             1    437ms  39.5%
   level 2.1       30    335ms  30.3%
   level 2.2        1    101ms  9.16%
 ────────────────────────────────────
```

It is possible to flatten this timer using the `TimerOutputs.flatten` function that accumulates the data for all sections with identical labels:

```julia
julia> to_flatten = TimerOutputs.flatten(to);

julia> show(to_flatten; compact = true, allocations = false)
 ──────────────────────────────────
 Section     ncalls     time   %tot
 ──────────────────────────────────
 nest 1           1    669ms  60.5%
 level 2.2       21    525ms  47.5%
 nest 2           1    437ms  39.5%
 level 2.1       31    436ms  39.5%
 ──────────────────────────────────
```

## Resetting

A timer is reset by calling `reset_timer!(to::TimerOutput)`. This will remove all sections and reset the start of the timer to the current time / allocation values.

## Indexing into a table

Any `TimerOutput` can be indexed with the name of a section which returns a new `TimerOutput` with that section as the "root". For example:


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
 -------------------------------------
 Section        ncalls     time   %tot
 -------------------------------------
 nest 1              1    605ms   100%
   nest 2            1    304ms  50.2%
     nest 3.2        1    101ms  16.7%
     nest 3.1        1    101ms  16.7%
     nest 3.3        1    101ms  16.7%
 -------------------------------------

julia> to_2 = to["nest 1"]["nest 2"];

julia> show(to_2; compact = true, allocations = false, linechars = :ascii)
 ---------------------------------
 Section    ncalls     time   %tot
 ---------------------------------
 nest 3.2        1    101ms  33.3%
 nest 3.1        1    101ms  33.3%
 nest 3.3        1    101ms  33.3%
 ---------------------------------
```

The percentages showed are now relative to that "root".

## Querying data

The (unexported) functions `ncalls`, `time`, `allocated` give the accumulated data for a section.
The returned time has units in nano seconds and allocations in bytes.
For example (using the `to` object from above):

```julia
julia> TimerOutputs.ncalls(to["nest 1"])
1

julia> TimerOutputs.time(to["nest 1"]["nest 2"])
350441733

julia> TimerOutputs.allocated(to["nest 1"]["nest 2"])
5280
```

Furthermore, you can request the total time spent in the "root" timer:

```julia
julia> TimerOutputs.tottime(to)
604937208

julia> TimerOutputs.totallocated(to)
7632
```

## Default Timer

It is often the case that it is enough to only use one timer. For convenience, there is therefore a version of
all the functions and macros that do not take a `TimerOutput` instance and then use a global timer defined in the package.
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
 ───────────────────────────────────────────────────────────────────
                            Time                   Allocations
                    ──────────────────────   ───────────────────────
  Tot / % measured:      276ms / 44.3%            422KiB / 0.21%

 Section    ncalls     time   %tot     avg     alloc   %tot      avg
 ───────────────────────────────────────────────────────────────────
 section2        1    101ms  82.7%   101ms      464B  50.0%     464B
 section         1   21.1ms  17.3%  21.1ms      464B  50.0%     464B
 ───────────────────────────────────────────────────────────────────
```

The default timer object can be retrieved with `TimerOutputs.get_defaulttimer()`.


## Overhead

There is a small overhead in timing a section (0.25 μs) which means that this package is not suitable for measuring sections that finish very quickly.
For proper benchmarking you want to use a more suitable tool like [*BenchmarkTools*](https://github.com/JuliaCI/BenchmarkTools.jl).

It is sometimes desireable to be able "turn on and off" the `@timeit` macro, for instance you may wish to instrument a package with `@timeit` macros, but then not deal with the overhead of the timings during normal package operation.
To enable this, we provide the `@timeit_debug` macro, which wraps the `@timeit` macro with a conditional, checking if debug timings have been enabled.
Because you may wish to turn on only certain portions of your instrumented code base (or multiple codebases may have instrumented their code), debug timings are enabled on a module-by-module basis.
By default, debug timings are disabled, and this conditional should be optimized away, allowing for truly zero-overhead.
If a user calls `TimerOutputs.enable_debug_timings(<module>)`, the `<module>.timeit_debug_enabled()` method will be redefined, causing all dependent methods to be recompiled within that module.
This may take a while, and hence is intended only for debugging usage, however all calls to `@timeit_debug` (within that Module) will thereafter be enabled.

## Author

Kristoffer Carlsson - @KristofferC

## Acknowledgments

This package is inspired by the `TimerOutput` class in [deal.ii](https://dealii.org/).
