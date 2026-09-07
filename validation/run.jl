# Power flow comparison against pandapower.
#
# This lives outside the package's test environment on purpose. PowerModels is not a
# dependency of SimBench.jl and should not become one just to be tested against, and the
# package's own suite runs on a seven leg matrix across three operating systems where a
# solver dependency would be paid for seven times. See .github/workflows/Validation.yml.
#
# Run it with:
#
#     julia --project=validation validation/run.jl

using DataFrames: eachrow, nrow
using PowerModels: PowerModels
using SimBench: SimBench
using Test: @test, @testset

include(joinpath(@__DIR__, "..", "test", "references.jl"))

PowerModels.silence()

"""
Dataset directory, or `nothing` if it cannot be obtained.

Mirrors the guard in `test/runtests.jl` so this suite is offline safe the same way.
"""
const DATASET = try
    SimBench.data_dir()
catch err
    @warn "SimBench dataset unavailable; power flow comparison will be skipped" err
    nothing
end

"""
    wrap_degrees(d) -> Float64

Fold an angle difference into the half open interval `(-180, 180]`.

Cascaded Dyn5 transformers shift by 150 degrees each, so a bus two transformers below the
slack sits 300 degrees away and the two implementations can report it a full turn apart.
That is the same physical angle, so the comparison is modulo one turn.
"""
wrap_degrees(d) = d - 360 * round(d / 360)

@testset "power flow against pandapower" begin
    if MANIFEST === nothing
        @info "Skipping power flow comparison: reference manifest missing."
    elseif DATASET === nothing
        @info "Skipping power flow comparison: dataset unavailable."
    else
        for row in eachrow(MANIFEST)
            @testset "$(row.code)" begin
                @test row.pf_converged

                grid = SimBench.read_grid(row.code; nrows = 1)
                topo = SimBench.resolve_topology(grid)
                data = SimBench.powermodels_data(grid; topology = topo)

                # compute_ac_pf is a native Newton-Raphson, so this needs no optimizer.
                # It starts from vm_start and va_start, which means a converging run is
                # also a regression test on the angle and magnitude seeding: without it
                # every bus starts a transformer shift away from its solution and the
                # iteration does not arrive.
                result = PowerModels.compute_ac_pf(data)
                @test result["termination_status"]

                solution = result["solution"]["bus"]
                reference = read_reference("powerflow", "$(row.code).bus.csv")
                @test nrow(reference) == row.pf_buses

                for r in eachrow(reference)
                    bus = solution[string(topo.bus_of[r.node_id])]
                    @test isapprox(bus["vm"], r.vm_pu; atol = row.vm_atol)
                    @test abs(wrap_degrees(rad2deg(bus["va"]) - r.va_degree)) <=
                        row.va_atol
                end
            end
        end
    end
end
