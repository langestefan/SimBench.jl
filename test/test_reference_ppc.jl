using DataFrames: eachrow

# Comparison against pandapower's internal per-unit values, captured in
# test/references/ppc/ by reference/generate_all.py.
#
# Everything is keyed by SimBench name. Buses key on node id, because the two
# implementations pick different representatives when they fuse a group, and branches key
# on element name, which is unique. Bus couplers exist only on this side, since
# pandapower fuses those switches instead of modelling them, so they are simply never
# looked up.

"""
Map each node id in `bus` to the bus it resolves to on each side.

Returns the node-to-group map, and whether the mapping is consistent: every node sharing
a converted bus must also share a pandapower group.
"""
function _bus_groups(topo, bus)
    groups = Dict{Int, Int}()
    consistent = true
    for r in eachrow(bus)
        b = topo.bus_of[r.node_id]
        if haskey(groups, b)
            groups[b] == r.ppc_bus || (consistent = false)
        else
            groups[b] = r.ppc_bus
        end
    end
    return groups, consistent
end

@testset "reference ppc" begin
    if MANIFEST === nothing
        @info "Skipping pandapower comparison: reference manifest missing."
    elseif DATASET === nothing
        @info "Skipping pandapower comparison: dataset unavailable."
    else
        for row in eachrow(MANIFEST)
            @testset "$(row.code)" begin
                # A reference regenerated without the tap_changer_type workaround would
                # pin every tap at 1.0. Fail on the reference itself, not on the taps.
                @test row.tap_changer_type_applied

                grid = SimBench.read_grid(row.code; nrows = 1)
                topo = SimBench.resolve_topology(grid)
                data = SimBench.powermodels_data(
                    grid; baseMVA = row.base_mva, topology = topo,
                    pq_as = :load, storage_as = :load, dc_as = :dcline,
                )

                bus = read_reference("ppc", "$(row.code).bus.csv")
                groups, consistent = _bus_groups(topo, bus)

                # The two fusion partitions must agree. For a no_sw code pandapower
                # deletes the absorbed buses, so equal counts plus an injective map is a
                # bijection, which proves the partitions are identical without ever
                # comparing the representatives the two sides happen to pick. For an sw
                # code pandapower keeps every bus and fuses only inside the ppc, so this
                # side is a refinement: consistent, but not injective.
                @test length(topo.buses) == row.n_pp_bus
                @test consistent
                if row.breaker_rep == "no_sw"
                    @test length(unique(values(groups))) == length(groups)
                end

                for r in eachrow(bus)
                    b = data["bus"][string(topo.bus_of[r.node_id])]
                    @test isapprox(b["base_kv"], r.base_kv; rtol = row.pu_rtol)
                end

                # Nodal injections, aggregated per pandapower group because a group can
                # cover several buses on this side. pandapower folds loads, static
                # generators and storage into the bus, which is why the conversion runs
                # with pq_as and storage_as set to :load here.
                pd = Dict{Int, Float64}()
                qd = Dict{Int, Float64}()
                for l in values(data["load"])
                    g = groups[l["load_bus"]]
                    pd[g] = get(pd, g, 0.0) + l["pd"]
                    qd[g] = get(qd, g, 0.0) + l["qd"]
                end
                for r in eachrow(bus)
                    @test isapprox(
                        get(pd, r.ppc_bus, 0.0) * row.base_mva, r.pd_mw;
                        atol = row.mw_atol,
                    )
                    @test isapprox(
                        get(qd, r.ppc_bus, 0.0) * row.base_mva, r.qd_mvar;
                        atol = row.mw_atol,
                    )
                end

                branch = read_reference("ppc", "$(row.code).branch.csv")
                by_name = Dict(b["name"] => b for b in values(data["branch"]))
                for r in eachrow(branch)
                    b = by_name[r.name]
                    @test isapprox(b["br_r"], r.br_r; rtol = row.pu_rtol, atol = row.pu_atol)
                    @test isapprox(b["br_x"], r.br_x; rtol = row.pu_rtol, atol = row.pu_atol)
                    @test isapprox(b["b_fr"] + b["b_to"], r.br_b; atol = row.pu_atol)
                    @test isapprox(b["g_fr"] + b["g_to"], r.br_g; atol = row.pu_atol)
                    @test isapprox(b["tap"], r.tap; atol = row.pu_atol)
                    @test isapprox(rad2deg(b["shift"]), r.shift_deg; atol = 1.0e-9)

                    # An end that is open sits on a stub bus here and on an internal
                    # auxiliary bus in pandapower, so only closed ends are comparable.
                    r.from_closed && @test topo.bus_of[r.from_node] == b["f_bus"]
                    r.to_closed && @test topo.bus_of[r.to_node] == b["t_bus"]
                    if r.from_closed && r.to_closed
                        @test b["br_status"] == r.br_status
                    end
                end

                gen = read_reference("ppc", "$(row.code).gen.csv")
                by_gen = Dict(g["name"] => g for g in values(data["gen"]))
                for r in eachrow(gen)
                    g = by_gen[r.name]
                    @test isapprox(g["vg"], r.vg_pu; rtol = row.pu_rtol)
                    @test topo.bus_of[r.node_id] == g["gen_bus"]
                end

                if row.n_dcline > 0
                    dcline = read_reference("ppc", "$(row.code).dcline.csv")
                    by_dc = Dict(d["name"] => d for d in values(data["dcline"]))
                    @test length(by_dc) == row.n_dcline
                    for r in eachrow(dcline)
                        d = by_dc[r.name]
                        @test topo.bus_of[r.from_node] == d["f_bus"]
                        @test topo.bus_of[r.to_node] == d["t_bus"]
                        @test isapprox(
                            d["pf"] * row.base_mva, r.p_mw; atol = row.mw_atol
                        )
                        @test isapprox(d["vf"], r.vm_from_pu; rtol = row.pu_rtol)
                        @test isapprox(d["vt"], r.vm_to_pu; rtol = row.pu_rtol)
                    end
                end
            end
        end
    end
end
