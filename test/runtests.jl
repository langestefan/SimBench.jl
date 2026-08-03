using SimBench
using Test
using Aqua

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
end
