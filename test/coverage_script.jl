# entrypoint to TestPkg to invoke `abc`
using Pkg, TimerOutputs

Pkg.develop(; path=joinpath(pkgdir(TimerOutputs), "test", "TestPkg"))
using TestPkg

TestPkg.abc()
