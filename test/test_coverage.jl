function find_cov_files()
    pkg = joinpath(pkgdir(TimerOutputs), "test", "TestPkg")
    return filter(endswith(".cov"), readdir(joinpath(pkg, "src"); join=true))
end

# remove existing coverage
foreach(rm, find_cov_files())

@testset "functions defined with `@timeit` macro generate code coverage" begin
    @test isempty(find_cov_files())

    script = joinpath(pkgdir(TimerOutputs), "test", "coverage_script.jl")
    run(`julia --startup-file=no --project=$(pkgdir(TimerOutputs)) --check-bounds=yes --code-coverage $script`)

    @test !isempty(find_cov_files())
end
