# TimerOutputs

[![Build Status](https://github.com/KristofferC/TimerOutputs.jl/workflows/CI/badge.svg)](https://github.com/KristofferC/TimerOutputs.jl/actions) [![codecov](https://codecov.io/gh/KristofferC/TimerOutputs.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/KristofferC/TimerOutputs.jl)

`TimerOutputs` is a small Julia package that is used to generate formatted output from timings made in different sections of a program.
It's main functionality is the `@timeit` macro, similar to the `@time` macro in Base except one also assigns a label to the code section being timed.
Multiple calls to code sections with the same label (and in the same "scope") will accumulate the data for that label.
After the program has executed, it is possible to print a nicely formatted table presenting how much time, allocations and number of calls were made in each section.
The output can be customized as to only show the things you are interested in.

If you find this package useful please give it a star. I like stars and it also helps me know where my development time is best spent.

## Example output

An example of the output (used in a finite element simulation) is shown below

```
              Total / % measured: 6.89s / 97.7%   5.20GiB / 84.9%
────────────────────────────────────────────────────────────────────────────────
                                        Time                 Allocations
 Section               ncalls    time    %tot     avg    alloc    %tot      avg
────────────────────────────────────────────────────────────────────────────────
 assemble                   6   3.27s   48.5%   545ms  3.65GiB   82.7%   623MiB
 └─ inner assemble       240k   1.92s   28.5%  8.00μs  3.14GiB   71.1%  13.7KiB
 linear solve               5   2.73s   40.5%   546ms   108MiB    2.4%  21.6MiB
 create sparse matrix       6   658ms    9.8%   110ms   662MiB   14.6%   110MiB
 export                     1  78.4ms    1.2%  78.4ms  13.1MiB    0.3%  13.1MiB
────────────────────────────────────────────────────────────────────────────────
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
    @timeit to "throwing" begin
        sleep(0.5)
        throw(error("this is fine..."))
        print("nope")
    end
end

i_will_throw()

# Use disable_timer! to selectively turn off a timer, enable_timer! turns it on again
disable_timer!(to)
@timeit to "not recorded" sleep(0.1)
enable_timer!(to)

# Use @notimeit to disable timer and re-enable it afterwards (if it was enabled
# before)
@notimeit to time_test()

# Call to a previously used label accumulates data
for i in 1:100
    @timeit to "sleep" sleep(0.01)
end

# Can also annotate function definitions
@timeit to funcdef(x) = x

funcdef(2)

# Or to instrument an existing function:
foo(x) = x + 1
timed_foo = to(foo)
timed_foo(5)

# Print the timings in the default way
show(to)
```

Printing `to` shows a formatted table showing the number of calls,
the total time spent in each section, and the percentage of the time
spent in each section since `to` was created as well as averages (per call).
Similar information is available for allocations:

```
           Total / % measured: 4.30s / 67.2%   103MiB / 81.9%
────────────────────────────────────────────────────────────────────────
                                Time                 Allocations
 Section       ncalls    time    %tot     avg    alloc    %tot      avg
────────────────────────────────────────────────────────────────────────
 sleep            101   1.14s   39.4%  11.3ms  16.7KiB    0.0%     169B
 nest 2             1   703ms   24.3%   703ms     944B    0.0%     944B
 ├─ level 2.2       1   401ms   13.9%   401ms     112B    0.0%     112B
 └─ level 2.1       1   302ms   10.4%   302ms     112B    0.0%     112B
 throwing           1   502ms   17.4%   502ms     512B    0.0%     512B
 nest 1             1   396ms   13.7%   396ms  1.36KiB    0.0%  1.36KiB
 ├─ level 2.2       1   201ms    7.0%   201ms     112B    0.0%     112B
 └─ level 2.1       3  93.2ms    3.2%  31.1ms     336B    0.0%     112B
 randoms            1   152ms    5.3%   152ms  84.2MiB  100.0%  84.2MiB
 funcdef            1  56.0ns    0.0%  56.0ns    0.00B    0.0%    0.00B
 foo                1  15.0ns    0.0%  15.0ns    0.00B    0.0%    0.00B
────────────────────────────────────────────────────────────────────────
```

It is also possible to manually start and stop a timed section.

```julia
section = begin_timed_section!(to, "my section")
foo()
end_timed_section!(to, section)
```

## Settings for printing:

The `print_timer([io::IO = stdout], to::TimerOutput, kwargs)`, (or `show`) takes a number of keyword arguments to change the output. They are listed here:

* `title::String` ─ title for the timer
* `allocations::Bool` ─ show the allocation columns (default `true`)
* `sortby::Symbol` ─ sort the sections according to `:time` (default), `:ncalls`, `:allocations`, `:name` or `:firstexec`
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
  Total / % measured: 1.07s / 98.7%
──────────────────────────────────────
                            Time
 Section       ncalls    time    %tot
──────────────────────────────────────
 nest 1             1   626ms   59.0%
 ├─ level 2.2      20   423ms   39.9%
 └─ level 2.1       1   101ms    9.5%
 nest 2             1   436ms   41.0%
 ├─ level 2.1      30   334ms   31.5%
 └─ level 2.2       1   101ms    9.5%
──────────────────────────────────────
```

It is possible to flatten this timer using the `TimerOutputs.flatten` function that accumulates the data for all sections with identical labels:

```julia
julia> to_flatten = TimerOutputs.flatten(to);

julia> show(to_flatten; compact = true, allocations = false)
 Total / % measured: 1.10s / 96.4%
───────────────────────────────────
                         Time
 Section    ncalls    time    %tot
───────────────────────────────────
 nest 1          1   626ms   59.0%
 level 2.2      21   524ms   49.4%
 nest 2          1   436ms   41.0%
 level 2.1      31   435ms   41.0%
───────────────────────────────────
```

## Merging

Two or more timers can be merged using `merge` or `merge!`:

```julia
julia> to1 = TimerOutput(); to2 = TimerOutput();

julia> @timeit to1 "outer" begin
           @timeit to1 "inner" begin
                sleep(1)
           end
       end

julia> @timeit to2 "outer" begin
           sleep(1)
       end

julia> show(to1; compact=true, allocations=false)
Total / % measured: 2.02s / 49.7%
──────────────────────────────────
                        Time
 Section   ncalls    time    %tot
──────────────────────────────────
 outer          1   1.01s  100.0%
 └─ inner       1   1.01s  100.0%
──────────────────────────────────

julia> show(to2; compact=true, allocations=false)
Total / % measured: 2.06s / 48.6%
─────────────────────────────────
                       Time
 Section  ncalls    time    %tot
─────────────────────────────────
 outer         1   1.00s  100.0%
─────────────────────────────────

julia> show(merge(to1, to2); compact=true, allocations=false)
Total / % measured: 2.04s / 98.3%
──────────────────────────────────
                        Time
 Section   ncalls    time    %tot
──────────────────────────────────
 outer          2   2.01s  100.0%
 └─ inner       1   1.00s   50.1%
──────────────────────────────────
```

Merging can be used to facilitate timing coverage throughout simple multi-threaded setups.
For instance, use thread-local `TimerOutput` objects that are merged at custom merge points
via the `tree_point` keyword arg, which is a vector of label strings used to navigate to
the merge point in the timing tree. `merge!` is thread-safe via a lock.

```julia
julia> using TimerOutputs

julia> to = TimerOutput()

julia> @timeit to "1" begin
    @timeit to "1.1" sleep(0.1)
    @timeit to "1.2" sleep(0.1)
    @timeit to "1.3" sleep(0.1)
end

julia> @timeit to "2" Threads.@spawn begin
    to2 = TimerOutput()
    @timeit to2 "2.1" sleep(0.1)
    @timeit to2 "2.2" sleep(0.1)
    @timeit to2 "2.3" sleep(0.1)
    merge!(to, to2, tree_point = ["2"])
end

julia> to
 ──────────────────────────────────────────────────────────────────
                           Time                   Allocations
                   ──────────────────────   ───────────────────────
 Tot / % measured:      3.23s / 9.79%           13.5MiB / 36.9%
 Section   ncalls     time   %tot     avg     alloc   %tot      avg
 ──────────────────────────────────────────────────────────────────
 1              1    309ms  98.0%   309ms   4.55MiB  91.5%  4.55MiB
   1.3          1    106ms  33.6%   106ms      320B  0.01%     320B
   1.2          1    102ms  32.3%   102ms      320B  0.01%     320B
   1.1          1    101ms  32.0%   101ms   4.54MiB  91.4%  4.54MiB
 2              1   6.47ms  2.05%  6.47ms    435KiB  8.54%   435KiB
   2.2          1    106ms  33.6%   106ms      480B  0.01%     480B
   2.3          1    105ms  33.4%   105ms      144B  0.00%     144B
   2.1          1    103ms  32.5%   103ms   5.03MiB  101%   5.03MiB
 ──────────────────────────────────────────────────────────────────
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

## Timing in multithreaded / concurrent code

A `TimerOutput` must only be used from one task at a time — timing sections on the
same instance concurrently from multiple threads or tasks will race. For
concurrent code, use a `ConcurrentTimerOutput` instead. It supports `@timeit`,
`@timeit_debug`, `@notimeit`, `begin_timed_section!`/`end_timed_section!` and the
functional `timeit` form, and can be freely shared between tasks:

```julia
const cto = ConcurrentTimerOutput()

function work(i)
    @timeit cto "work" begin
        @timeit cto "step" step(i)
    end
end

foreach(wait, [Threads.@spawn work(i) for i in 1:100])
print_timer(cto)
```

Internally each task records into its own private timer tree (an extra cost of a
few ns per section over a plain `TimerOutput`), and the trees are combined by
section label whenever the timer is printed or queried. Semantics to be aware of:

* The time reported for a section is the **sum of the wall clock time every task
  spent inside it**, including time where a task was waiting or descheduled. With
  parallelism the measured percentage therefore exceeds 100% — e.g. 8 continuously
  busy tasks approach 800% of the elapsed time.
* Queries (`getindex`, `TimerOutputs.ncalls`, ...) and `TimerOutput(cto)` return
  detached snapshot copies. Snapshots taken while sections are in flight are
  approximately consistent; they are exact once the timed tasks have finished.
* Sections that are in flight while `reset_timer!` is called may or may not be
  counted.

Alternatively, the manual pattern from the previous section — one plain
`TimerOutput` per task, combined with `merge!` at a join point — remains fully
supported and has zero extra cost in the timed sections.

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
         Total / % measured: 152ms / 80.4%   1.50MiB / 0.1%
────────────────────────────────────────────────────────────────────
                            Time                 Allocations
 Section   ncalls    time    %tot     avg    alloc    %tot      avg
────────────────────────────────────────────────────────────────────
 section2       1   101ms   82.7%   101ms     400B   50.0%     400B
 section        1  21.1ms   17.3%  21.1ms     400B   50.0%     400B
────────────────────────────────────────────────────────────────────
```

The default timer object can be retrieved with `TimerOutputs.get_defaulttimer()`.

## Measuring time consumed outside `@timeit` blocks

Often, operations that we do not consider time consuming turn out to be relevant.
However, adding additional timming blocks just to time initializations and other
less important calls is annoying.

The `TimerOutputs.complement!` function can be used to modify a timer and add
values for complement of timed sections. For instance:

```julia
to = TimerOutput()

@timeit to "section1" sleep(0.02)
@timeit to "section2" begin
    @timeit to "section2.1" sleep(0.1)
    sleep(0.01)
end

TimerOutputs.complement!(to)
```

We can print the result:

```julia
julia> print_timer(to)
           Total / % measured: 143ms / 95.6%   73.4KiB / 10.0%
─────────────────────────────────────────────────────────────────────────
                                 Time                 Allocations
 Section        ncalls    time    %tot     avg    alloc    %tot      avg
─────────────────────────────────────────────────────────────────────────
 section2            1   112ms   82.4%   112ms  1.77KiB   24.0%  1.77KiB
 ├─ section2.1       1   101ms   74.2%   101ms     400B    5.3%     400B
 └─ ~section2~       1  11.2ms    8.2%  11.2ms  1.38KiB   18.7%  1.38KiB
 section1            1  24.1ms   17.6%  24.1ms  5.58KiB   76.0%  5.58KiB
─────────────────────────────────────────────────────────────────────────
```

In order to complement the default timer simply call `TimerOutputs.complement!()`.

## Shared Timers

It is sometimes desirable for a timer to be shared across all users of the
package.  For this purpose, `get_timer` maintains a collection of named timers
defined in the package.

`get_timer(timer_name::String)` retrieves the timer `timer_name` from the
collection, creating a new timer if none already exists.

For example:
```julia
module UseTimer
using TimerOutputs: @timeit, get_timer

function foo()
    to = get_timer("Shared")
    @timeit get_timer("Shared") "foo" sleep(0.1)
end
end

@timeit get_timer("Shared") "section1" begin
    UseTimer.foo()
    sleep(0.01)
end
```

which prints:
```julia
julia> print_timer(get_timer("Shared"))
        Total / % measured: 127ms / 99.9%   1.36MiB / 99.8%
────────────────────────────────────────────────────────────────────
                            Time                 Allocations
 Section   ncalls    time    %tot     avg    alloc    %tot      avg
────────────────────────────────────────────────────────────────────
 section1       1   127ms  100.0%   127ms  1.35MiB  100.0%  1.35MiB
 └─ foo         1   101ms   79.7%   101ms     224B    0.0%     224B
────────────────────────────────────────────────────────────────────
```

Note that the result of `get_timer` should not be called from top-level in a
package that is getting precompiled since the retrieved timer will no longer be
shared with other users getting a timer with the same name. Also, this function
is not recommended to be used extensively by libraries as the namespace is
shared and collisions are possible if two libraries happen to use the same timer
name.

## Serialization

Timers may be converted to a nested set of dictionaries with the (unexported) `TimerOutputs.todict` function. This can be used to serialize a timer as JSON, for example.

```julia
julia> to = TimerOutput();

julia> @timeit to "nest 1" begin
           sleep(0.1)
           @timeit to "level 2.1" sleep(0.1)
           for i in 1:20; @timeit to "level 2.2" sleep(0.02); end
       end

julia> TimerOutputs.todict(to)
Dict{String, Any} with 6 entries:
  "total_time_ns" => 726721166
  "total_allocated_bytes" => 474662
  "time_ns" => 0
  "n_calls" => 0
  "allocated_bytes" => 0
  "inner_timers" => Dict{String, Any}("nest 1"=>Dict{String, Any}("total_time_ns"=>611383374, "total_allocated_bytes"=>11888, "time_ns"=>726721166, "n_calls"=>1, "allocated_bytes"=>474662, "inner_timers"=>Dict{String, Any}("level 2.1"=>Dict{String, Any}("total_time_ns"=>0, "total_allocated_bytes"=>0, "time_ns"=>115773750, "n_calls"=>1, "allocated_bytes"=>8064, "inner_timers"=>Dict{String, Any}()), "level 2.2"=>Dict{String, Any}("total_time_ns"=>0, "total_allocated_bytes"=>0, "time_ns"=>495609624, "n_calls"=>20, "allocated_bytes"=>3824, "inner_timers"=>Dict{String, Any}()))))

julia> using JSON3 # or JSON

julia> JSON3.write(TimerOutputs.todict(to))
"{\"total_time_ns\":712143250,\"total_allocated_bytes\":5680,\"time_ns\":0,\"n_calls\":0,\"allocated_bytes\":0,\"inner_timers\":{\"nest 1\":{\"total_time_ns\":605922416,\"total_allocated_bytes\":4000,\"time_ns\":712143250,\"n_calls\":1,\"allocated_bytes\":5680,\"inner_timers\":{\"level 2.1\":{\"total_time_ns\":0,\"total_allocated_bytes\":0,\"time_ns\":106111333,\"n_calls\":1,\"allocated_bytes\":176,\"inner_timers\":{}},\"level 2.2\":{\"total_time_ns\":0,\"total_allocated_bytes\":0,\"time_ns\":499811083,\"n_calls\":20,\"allocated_bytes\":3824,\"inner_timers\":{}}}}}}"
```

## FlameGraphs

TimerOutputs has a FlameGraph extension that provides an alternative visualization method.

i.e. using ProfileView.jl
```
using TimerOutputs, FlameGraphs, ProfileView
to = TimerOutput()
@timeit to "foo" begin
    sleep(0.1)
    @timeit to "bar" begin
        sleep(0.1)
        @timeit to "baz" begin
            sleep(0.1)
        end
    end
end
ProfileView.view(flamegraph(to))
```

You may want to crop the span of the graph to the children, not how long `to` has been open.
To do that use `crop_root=true`
```
ProfileView.view(flamegraph(to, crop_root=true))
```

## Overhead

There is a small overhead in timing a section (~30 ns on a modern machine, dominated by reading the clock) which means that this package is not suitable for measuring sections that finish very quickly.
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
