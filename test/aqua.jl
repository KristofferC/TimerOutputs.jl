using Aqua
using TimerOutputs

# Full Aqua quality suite. Printf (a dep) and Test (a test-only extra) are
# pure-stdlib dependencies pinned by the `julia` compat bound and carry no
# independent version, so they're excluded from the [compat] completeness
# check; every other dependency is still verified.
Aqua.test_all(
    TimerOutputs;
    deps_compat = (
        ignore = [:Printf],
        check_extras = (ignore = [:Test],),
    ),
)
