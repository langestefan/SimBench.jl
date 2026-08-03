using DataFrames: nrow

# Reference per-unit values taken from pandapower's internal ppc arrays for
# 1-LV-rural1--0-no_sw, on pandapower's own 1 MVA base. These pin down the whole
# transformer model: short-circuit impedance referred to the low-voltage side, the T to
# pi conversion of the magnetising branch, the off-nominal tap ratio and the Dyn5 shift.
const PP_TRAFO = (
    name = "MV1.101-LV1.101-Trafo 1",
    br_r = 0.0917916665826,
    br_x = 0.232541689721,
    b_total = -3.8489176465e-6,
    g_total = 0.000459994938812,
    tap = 1.0,
    shift = 150.0,
)

@testset "powermodels" begin
    @testset "T to pi conversion" begin
        # With no magnetising branch the impedance passes through untouched.
        @test SimBench._t_to_pi(0.1, 0.2, 0.0, 0.0) == (0.1, 0.2, 0.0, 0.0)

        # The two circuits must be indistinguishable from outside, so compare their
        # two-port admittance parameters.
        r, x, g, b = 0.05, 0.2, 1.0e-3, -2.0e-3
        rp, xp, gs, bs = SimBench._t_to_pi(r, x, g, b)

        za = zb = complex(r, x) / 2          # leakage, split evenly
        zc = 1 / complex(g, b)               # magnetising branch
        delta = za * zb + za * zc + zb * zc
        t_y11, t_y12 = (zb + zc) / delta, -zc / delta

        y_series, y_shunt = 1 / complex(rp, xp), complex(gs, bs)
        pi_y11, pi_y12 = y_series + y_shunt, -y_series

        @test isapprox(t_y11, pi_y11; rtol = 1.0e-12)
        @test isapprox(t_y12, pi_y12; rtol = 1.0e-12)

        # Even split in, symmetric circuit out.
        @test isapprox((za + zc) / delta, pi_y11; rtol = 1.0e-12)
    end

    @testset "rejects bad options" begin
        if DATASET !== nothing
            grid = SimBench.read_grid("1-LV-rural1--0-no_sw"; nrows = 1)
            @test_throws ArgumentError SimBench.powermodels_data(grid; pq_as = :nope)
            @test_throws ArgumentError SimBench.powermodels_data(grid; dc_as = :nope)
            @test_throws ArgumentError SimBench.powermodels_data(
                grid; storage_as = :nope
            )
        end
    end

    @testset "case structure" begin
        if DATASET === nothing
            @info "Skipping PowerModels conversion tests: dataset unavailable."
        else
            grid = SimBench.read_grid("1-LV-rural1--0-no_sw"; nrows = 1)
            topo = SimBench.resolve_topology(grid)
            data = SimBench.powermodels_data(grid; topology = topo)

            @test data["per_unit"] == true
            @test data["baseMVA"] == 100.0
            @test data["name"] == "1-LV-rural1--0-no_sw"
            @test data["source_type"] == "simbench"

            # One bus per resolved bus, indexed 1:n and self-consistent.
            @test length(data["bus"]) == length(topo.buses)
            for (k, bus) in data["bus"]
                @test bus["index"] == parse(Int, k)
                @test bus["bus_i"] == bus["index"]
                @test bus["base_kv"] > 0
            end

            # Exactly one slack, at the external network's node.
            refs = [b for b in values(data["bus"]) if b["bus_type"] == 3]
            @test length(refs) == 1
            @test refs[1]["name"] == grid[:ExternalNet].node[1]

            # Branches carry every line and transformer, and reference real buses.
            @test length(data["branch"]) ==
                nrow(grid[:Line]) + nrow(grid[:Transformer])
            @test count(b -> b["transformer"], values(data["branch"])) ==
                nrow(grid[:Transformer])
            for br in values(data["branch"])
                @test 1 <= br["f_bus"] <= length(data["bus"])
                @test 1 <= br["t_bus"] <= length(data["bus"])
            end

            # No published scenario has shunts or three-winding transformers.
            @test isempty(data["shunt"])
            @test isempty(data["storage"])
        end
    end

    @testset "against pandapower's per-unit values" begin
        if DATASET === nothing
            @info "Skipping per-unit comparison: dataset unavailable."
        else
            # Build on pandapower's 1 MVA base so the numbers are directly comparable.
            grid = SimBench.read_grid("1-LV-rural1--0-no_sw"; nrows = 1)
            data = SimBench.powermodels_data(grid; baseMVA = 1.0)
            br = only(
                b for b in values(data["branch"]) if b["name"] == PP_TRAFO.name
            )

            @test isapprox(br["br_r"], PP_TRAFO.br_r; rtol = 1.0e-9)
            @test isapprox(br["br_x"], PP_TRAFO.br_x; rtol = 1.0e-9)
            @test isapprox(br["b_fr"] + br["b_to"], PP_TRAFO.b_total; rtol = 1.0e-9)
            @test isapprox(br["g_fr"] + br["g_to"], PP_TRAFO.g_total; rtol = 1.0e-9)
            @test isapprox(br["tap"], PP_TRAFO.tap; rtol = 1.0e-12)
            @test isapprox(rad2deg(br["shift"]), PP_TRAFO.shift; atol = 1.0e-9)

            # The pi circuit is symmetric, since the leakage is split evenly.
            @test br["g_fr"] == br["g_to"]
            @test br["b_fr"] == br["b_to"]
        end
    end

    @testset "pq elements" begin
        if DATASET === nothing
            @info "Skipping pq element tests: dataset unavailable."
        else
            grid = SimBench.read_grid("1-LV-rural1--0-no_sw"; nrows = 1)
            n_res = nrow(grid[:RES])
            n_load = nrow(grid[:Load])
            @test n_res > 0

            # As negative loads, which is what pandapower does with a static generator.
            as_load = SimBench.powermodels_data(grid; pq_as = :load)
            @test length(as_load["load"]) == n_load + n_res
            @test length(as_load["gen"]) == nrow(grid[:ExternalNet])
            # Every generator sits on a PV or slack bus, as the NR power flow requires.
            for (_, g) in as_load["gen"]
                @test as_load["bus"]["$(g["gen_bus"])"]["bus_type"] in (2, 3)
            end
            # The injections are negative.
            @test any(l["pd"] < 0 for l in values(as_load["load"]))

            # As generators instead.
            as_gen = SimBench.powermodels_data(grid; pq_as = :gen)
            @test length(as_gen["load"]) == n_load
            @test length(as_gen["gen"]) == nrow(grid[:ExternalNet]) + n_res
            # Non-dispatchable, so active power is pinned.
            pinned = [g for g in values(as_gen["gen"]) if g["pmin"] == g["pmax"]]
            @test length(pinned) == n_res
        end
    end

    @testset "angle seeding" begin
        if DATASET === nothing
            @info "Skipping angle seeding tests: dataset unavailable."
        else
            grid = SimBench.read_grid("1-LV-rural1--0-no_sw"; nrows = 1)
            seeded = SimBench.powermodels_data(grid)
            flat = SimBench.powermodels_data(grid; seed_angles = false)

            # PowerModels reads a variable's start from the _start keys.
            @test all(haskey(b, "va_start") for b in values(seeded["bus"]))
            @test all(haskey(b, "vm_start") for b in values(seeded["bus"]))
            @test !any(haskey(b, "va_start") for b in values(flat["bus"]))

            # The low-voltage side sits a Dyn5 shift away from the reference, so the
            # seeded angles must span roughly 150 degrees rather than all being zero.
            angles = rad2deg.(b["va_start"] for b in values(seeded["bus"]))
            @test minimum(angles) < -140
            @test maximum(angles) <= 0.001

            # Load buses start at the mean of the controlled-bus setpoints, matching
            # pandapower's "auto" initialisation. Starting them at 1.0 next to buses
            # held near 1.09 pu puts an artificial voltage gradient across every line,
            # which is what kept Newton-Raphson from converging on the EHV grids.
            ctrl = [b["vm"] for b in values(seeded["bus"]) if b["bus_type"] != 1]
            starts = unique(
                b["vm_start"] for b in values(seeded["bus"]) if b["bus_type"] == 1
            )
            @test length(starts) == 1
            @test only(starts) ≈ sum(ctrl) / length(ctrl)
        end
    end

    @testset "angle limits admit the Dyn5 shift" begin
        if DATASET !== nothing
            grid = SimBench.read_grid("1-LV-rural1--0-no_sw"; nrows = 1)
            data = SimBench.powermodels_data(grid)
            # A limit below the 150 degree shift would make the case infeasible.
            for (_, br) in data["branch"]
                @test rad2deg(br["angmax"]) >= 150
                @test rad2deg(br["angmin"]) <= -150
            end
        end
    end

    @testset "dc lines and storage" begin
        if DATASET === nothing
            @info "Skipping dc line tests: dataset unavailable."
        else
            # The scenario 1 extra-high-voltage grid has two HVDC links and four
            # storage units.
            grid = SimBench.read_grid("1-EHV-mixed--1-no_sw"; nrows = 1)
            dc_types = Set(skipmissing(grid[:DCLineType].id))
            dc_ids = Set(
                id for (id, t) in zip(grid[:Line].id, grid[:Line].type) if
                    !ismissing(t) && t in dc_types
            )
            n_dc = length(dc_ids)
            @test n_dc == 2

            # By default each link becomes a pair of voltage-controlled generators,
            # from pandapower's own power flow representation.
            data = SimBench.powermodels_data(grid)
            dcgens = [
                g for g in values(data["gen"]) if g["source_id"][1] == "dcline"
            ]
            @test length(dcgens) == 2 * n_dc
            @test isempty(data["dcline"])
            for g in dcgens
                @test g["vg"] > 1
                @test data["bus"]["$(g["gen_bus"])"]["bus_type"] in (2, 3)
                @test data["bus"]["$(g["gen_bus"])"]["vm"] == g["vg"]
            end
            # The DC rows do not appear among the AC branches.
            @test all(b["name"] ∉ dc_ids for b in values(data["branch"]))
            @test Set(g["name"] for g in dcgens) == dc_ids

            # As PowerModels dcline components instead.
            as_dc = SimBench.powermodels_data(grid; dc_as = :dcline)
            @test length(as_dc["dcline"]) == n_dc
            @test length(as_dc["gen"]) == length(data["gen"]) - 2 * n_dc
            for dcl in values(as_dc["dcline"])
                @test dcl["br_status"] == 1
                @test dcl["loss1"] == 0.012
                @test dcl["vf"] > 1 && dcl["vt"] > 1
                # Losses tie the two setpoints together, per unit.
                @test dcl["pt"] ≈ dcl["loss0"] - (1 - dcl["loss1"]) * dcl["pf"]
            end

            # Storage as components by default, as equivalent loads on request.
            @test length(data["storage"]) == nrow(grid[:Storage])
            as_load = SimBench.powermodels_data(grid; storage_as = :load)
            @test isempty(as_load["storage"])
            stloads = [
                l for l in values(as_load["load"]) if l["source_id"][1] == "storage"
            ]
            @test length(stloads) == nrow(grid[:Storage])
            # These units discharge, so as loads they inject.
            @test all(l["pd"] < 0 for l in stloads)
        end
    end

    @testset "sw variant keeps couplers as branches" begin
        if DATASET !== nothing
            grid = SimBench.read_grid("1-LV-rural1--0-sw"; nrows = 1)
            data = SimBench.powermodels_data(grid)
            couplers = [
                b for b in values(data["branch"]) if b["source_id"][1] == "branch" &&
                    startswith(b["source_id"][2], "coupler")
            ]
            @test !isempty(couplers)
            for c in couplers
                @test c["br_r"] == 0.0
                @test c["br_x"] == 1.0e-6
            end
            # More buses than the collapsed variant, since auxiliary nodes stay.
            collapsed = SimBench.powermodels_data(
                SimBench.read_grid("1-LV-rural1--0-no_sw"; nrows = 1)
            )
            @test length(data["bus"]) > length(collapsed["bus"])
        end
    end

    @testset "open-ended branches are out of service" begin
        if DATASET !== nothing
            grid = SimBench.read_grid("1-MV-rural--0-no_sw"; nrows = 1)
            topo = SimBench.resolve_topology(grid)
            data = SimBench.powermodels_data(grid; topology = topo)
            out = [b for b in values(data["branch"]) if b["br_status"] == 0]
            # The six normally-open loop lines of this grid.
            @test length(out) == 6
            @test all(occursin("loop_line", b["name"]) for b in out)
        end
    end
end
