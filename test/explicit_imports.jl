using ExplicitImports: test_all_qualified_accesses_via_owners,
    test_no_implicit_imports, test_no_self_qualified_accesses,
    test_no_stale_explicit_imports
using Test
using TimerOutputs
using FlameGraphs   # loads the FlameGraphsExt extension so it is checked too

@testset "ExplicitImports.jl" begin
    ext = Base.get_extension(TimerOutputs, :FlameGraphsExt)
    @test ext !== nothing
    for mod in (TimerOutputs, ext)
        test_no_implicit_imports(mod)
        test_no_stale_explicit_imports(mod)
        test_all_qualified_accesses_via_owners(mod)
        test_no_self_qualified_accesses(mod)
    end
end
