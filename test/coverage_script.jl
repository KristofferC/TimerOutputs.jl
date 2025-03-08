# entrypoint to TestPkg to invoke `abc`
using TimerOutputs

push!(LOAD_PATH, joinpath(pkgdir(TimerOutputs),  "test", "TestPkg"))
try
    using TestPkg

    TestPkg.abc()
finally
    pop!(LOAD_PATH)
end
