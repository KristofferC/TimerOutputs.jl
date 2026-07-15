using JET
using Test
using TimerOutputs
using FlameGraphs

const FlameGraphsExt = Base.get_extension(TimerOutputs, :FlameGraphsExt)
FlameGraphsExt === nothing && error("the FlameGraphsExt extension did not load")

@testset "JET.jl" begin
    JET.test_package(TimerOutputs; target_modules = (TimerOutputs,), toplevel_logger = nothing)
end

@testset "JET FlameGraphsExt" begin
    JET.test_package(FlameGraphsExt; target_modules = (FlameGraphsExt, TimerOutputs), toplevel_logger = nothing)
end
