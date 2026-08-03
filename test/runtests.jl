using SimBench
using Test
using Aqua

"""
Dataset directory, or `nothing` if it cannot be obtained.

Normally this downloads the lazy artifact on first run. It only comes back `nothing`
when there is no network and no local copy configured, in which case the tests that
need real data skip themselves rather than fail.
"""
const DATASET = try
    SimBench.data_dir()
catch err
    @warn "SimBench dataset unavailable; dataset tests will be skipped" err
    nothing
end

"""
Dataset directory inside the artifact, or `nothing` if it cannot be downloaded.

Distinct from [`DATASET`](@ref), which honours a `SIMBENCH_DATA_DIR` override and so may
point at a local copy instead.
"""
const ARTIFACT_DIR = try
    SimBench.artifact_data_dir()
catch
    nothing
end

@testset "SimBench.jl" begin
    @testset "Code quality (Aqua)" begin
        Aqua.test_all(SimBench)
    end

    include("test_schema.jl")
    include("test_data_source.jl")
    include("test_codes.jl")
    include("test_voltlvl.jl")
    include("test_io.jl")
    include("test_extract.jl")
    include("test_grid.jl")
    include("test_switches.jl")
    include("test_powermodels.jl")
end
