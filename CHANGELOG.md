# TimerOutputs changelog

## Version 1.0.0

TimerOutputs 1.0 is a rewrite of the package internals with a number of new
features. The documented API of 0.5 keeps working; code that relied on
undocumented internals may need updating (see "Breaking" below).

### New features

* **Timing in concurrent code**: the new `ConcurrentTimerOutput` can be shared
  freely between tasks and threads. Each task transparently records into its
  own private tree (a few ns extra per section); the trees are merged by
  section label whenever the timer is printed or queried. See the README
  section on multithreaded timing for the semantics.
* **Zero-overhead timer disabling**: the new `NoTimerOutput` is a dummy timer
  where all operations are no-ops. When its type is known to the compiler
  (a `const`, or a type parameter of the struct holding it), `@timeit`
  sections compile away entirely — a per-timer alternative to
  `@timeit_debug`. Runtime-disabled regular timers also became ~10x cheaper
  (~1.4 ns per section).
* **Tables.jl interface**: timers are tables — `DataFrame(to)`,
  `CSV.write("timings.csv", to)` and any other Tables.jl consumer work
  directly, with one row per section holding the raw measurements
  (`path`, `section`, `depth`, `ncalls`, `time_ns`, `allocated_bytes`,
  `firstexec_ns`).
* **New table layout** (now built on PrettyTables.jl): tree guides (`├─`, `└─`)
  instead of plain indentation, grouped `Time` / `Allocations` headers, and a
  new `%par` column showing each section's share of its enclosing section.
* **Column selection**: `print_timer(to; columns = [:ncalls, :time, :time_pct])`
  picks exactly which columns to show, in order; `allocations` and `compact`
  remain as shorthands.
* **`maxdepth` keyword**: limit how deeply nested sections are printed.
* **`complement = true` display option**: show what was *not* timed, in gray —
  an `~untimed~` row for the wall time outside all sections, and a `~name~`
  row under each section for the part not covered by its subsections.
  Non-mutating alternative to `complement!`.
* **Nested indexing and iteration**: `to["a", "b"]` is `to["a"]["b"]`, and
  `keys(to)` iterates section names in insertion order.
* Sections themselves print as tables, and timers inside containers (arrays,
  dicts, struct fields) print as a one line summary instead of a full table.
* Tables are cropped to the terminal width instead of wrapping, and
  `linechars = :ascii` output is now pure ASCII (`us` instead of `μs`).

### Fixes

* Functions defined through `@timeit function f() ... end` keep the line
  numbers of their body, so stacktraces, coverage and profiling point at the
  right lines.
* `reset_timer!` while inside a timed section no longer throws.
* `merge`d timers report a sensible "% measured" (the measurement period now
  spans the inputs).
* Sections that never finished print `-` instead of `NaN`.
* `@timeit to "label" x` works for any expression, including literals and
  symbols, and invalid macro usage gives a proper error message.
* `copy(::TimerOutput)` returns a fully detached copy.

### Performance

* The `@timeit` hot path is unchanged: ~31 ns and 0 allocations per section.
* Timer trees use about half the memory (measurements stored inline in the
  nodes; children in insertion-ordered vectors).
* `merge`/`merge!` is an order of magnitude faster; `flatten` about twice as fast.
* Time to first printed table is ~3x faster (the rendering pipeline is
  precompiled), at the cost of a larger load time (~120 ms) from the
  PrettyTables dependency.

### Breaking

* PrettyTables.jl and Tables.jl are new dependencies.
* The printed table looks different (see above); output-parsing code needs
  updating.
* The tree nodes returned by `to["label"]` are now `Section`s rather than
  `TimerOutput`s, with the measurements as fields (`ncalls`, `time`,
  `allocs`, `firstexec`). The commonly used 0.5 internals remain readable
  (`to.inner_timers` returns a fresh `Dict`, `x.accumulated_data` carries the
  old field names), but mutating a timer through them is not supported.
* `TimerOutputs.TimeData` no longer exists.
