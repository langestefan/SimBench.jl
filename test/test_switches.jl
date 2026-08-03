using DataFrames: DataFrame, nrow

"""Minimal table set for topology tests: `node` and `switch` given, the rest optional."""
function topo_tables(; node, switch, line = nothing, trafo = nothing)
    return Dict{Symbol, DataFrame}(
        :Node => node,
        :Switch => switch,
        :Line => line === nothing ? DataFrame(id = String[], nodeA = String[], nodeB = String[]) : line,
        :Transformer => trafo === nothing ?
            DataFrame(id = String[], nodeHV = String[], nodeLV = String[]) : trafo,
    )
end

@testset "switches" begin
    @testset "auxiliary node collapse" begin
        # busbar --closed switch-- aux --line-- aux --closed switch-- busbar
        node = DataFrame(
            id = ["b1", "b2", "a1", "a2"],
            type = ["busbar", "busbar", "auxiliary", "auxiliary"],
        )
        switch = DataFrame(
            id = ["s1", "s2"], nodeA = ["b1", "b2"], nodeB = ["a1", "a2"],
            cond = [1, 1],
        )
        line = DataFrame(id = ["l1"], nodeA = ["a1"], nodeB = ["a2"])
        top = SimBench.resolve_topology(topo_tables(; node, switch, line))

        # Only the two real buses survive, and the auxiliary nodes map onto them.
        @test top.buses == ["b1", "b2"]
        @test SimBench.bus_of(top, "a1") == 1
        @test SimBench.bus_of(top, "a2") == 2
        @test SimBench.bus_of(top, "b1") == 1
        @test top.line_closed == BitVector([true])
        @test isempty(top.retyped)
    end

    @testset "open switch takes its branch out of service" begin
        node = DataFrame(
            id = ["b1", "b2", "a1", "a2"],
            type = ["busbar", "busbar", "auxiliary", "auxiliary"],
        )
        switch = DataFrame(
            id = ["s1", "s2"], nodeA = ["b1", "b2"], nodeB = ["a1", "a2"],
            cond = [1, 0],
        )
        line = DataFrame(id = ["l1"], nodeA = ["a1"], nodeB = ["a2"])
        top = SimBench.resolve_topology(topo_tables(; node, switch, line))
        @test top.line_closed == BitVector([false])

        # The auxiliary node still maps to its bus; only the branch is affected.
        @test SimBench.bus_of(top, "a2") == 2
    end

    @testset "branch ends without a switch" begin
        # A branch sitting straight on a busbar has no switch, and counts as closed.
        node = DataFrame(id = ["b1", "b2"], type = ["busbar", "busbar"])
        switch = DataFrame(id = String[], nodeA = String[], nodeB = String[], cond = Int[])
        line = DataFrame(id = ["l1"], nodeA = ["b1"], nodeB = ["b2"])
        top = SimBench.resolve_topology(topo_tables(; node, switch, line))
        @test top.buses == ["b1", "b2"]
        @test top.line_closed == BitVector([true])
    end

    @testset "promotion of multi-switch auxiliary nodes" begin
        # A double-busbar selector: one branch end reaching either busbar.
        node = DataFrame(
            id = ["b1", "b2", "sel"], type = ["busbar", "busbar", "auxiliary"],
        )
        switch = DataFrame(
            id = ["s1", "s2"], nodeA = ["b1", "b2"], nodeB = ["sel", "sel"],
            cond = [1, 0],
        )
        @test SimBench.multi_switch_aux_nodes(node, switch) == Set(["sel"])

        # Promoted, so it is a bus rather than something to collapse away.
        top = SimBench.resolve_topology(
            topo_tables(; node, switch); collapse = false
        )
        @test top.retyped == ["sel"]
        @test length(top.buses) == 3
        @test length(top.bus_switches) == 2

        # Upstream forces couplers closed, fusing both busbars with the selector.
        fused = SimBench.resolve_topology(topo_tables(; node, switch))
        @test length(fused.buses) == 1
        @test sort(fused.members[1]) == ["b1", "b2", "sel"]

        # Respecting the open switch keeps the second busbar apart.
        kept = SimBench.resolve_topology(
            topo_tables(; node, switch); respect_open_switches = true
        )
        @test length(kept.buses) == 2
        @test sort(kept.members[SimBench.bus_of(kept, "b1")]) == ["b1", "sel"]
        @test kept.members[SimBench.bus_of(kept, "b2")] == ["b2"]
    end

    @testset "bus couplers" begin
        node = DataFrame(id = ["b1", "b2", "b3"], type = ["busbar", "busbar", "busbar"])
        switch = DataFrame(
            id = ["tie1", "tie2"], nodeA = ["b1", "b2"], nodeB = ["b2", "b3"],
            cond = [1, 1],
        )
        # Fusion is transitive across a chain of closed couplers.
        top = SimBench.resolve_topology(topo_tables(; node, switch))
        @test length(top.buses) == 1
        @test sort(top.members[1]) == ["b1", "b2", "b3"]
        @test isempty(top.bus_switches)

        # Without collapsing, the buses stay apart and the couplers are reported.
        kept = SimBench.resolve_topology(topo_tables(; node, switch); collapse = false)
        @test length(kept.buses) == 3
        @test sort(kept.bus_switches) == [(1, 2, true), (2, 3, true)]
    end

    @testset "malformed topologies" begin
        node = DataFrame(id = ["b1", "a1", "a2"], type = ["busbar", "auxiliary", "auxiliary"])
        # Two auxiliary nodes cannot be joined directly.
        switch = DataFrame(id = ["s"], nodeA = ["a1"], nodeB = ["a2"], cond = [1])
        @test_throws ArgumentError SimBench.resolve_topology(topo_tables(; node, switch))

        # A switch to a node that does not exist.
        switch2 = DataFrame(id = ["s"], nodeA = ["b1"], nodeB = ["ghost"], cond = [1])
        @test_throws ArgumentError SimBench.resolve_topology(
            topo_tables(; node, switch = switch2)
        )
    end

    @testset "code drives the default variant" begin
        configured = get(ENV, SimBench.DATA_DIR_ENV, nothing)
        if configured === nothing || !isdir(configured)
            @info "Skipping topology tests: set $(SimBench.DATA_DIR_ENV) to enable."
        else
            SimBench.reset_data_dir!()
            grid_sw = SimBench.read_grid("1-MV-rural--0-sw"; nrows = 1)
            grid_no = SimBench.read_grid("1-MV-rural--0-no_sw"; nrows = 1)

            # An sw code keeps the couplers; a no_sw code collapses them.
            @test !isempty(SimBench.resolve_topology(grid_sw).bus_switches)
            @test isempty(SimBench.resolve_topology(grid_no).bus_switches)
            @test length(SimBench.resolve_topology(grid_no).buses) <
                length(SimBench.resolve_topology(grid_sw).buses)
        end
    end

    @testset "whole scenario" begin
        configured = get(ENV, SimBench.DATA_DIR_ENV, nothing)
        if configured === nothing || !isdir(configured)
            @info "Skipping scenario topology tests: set $(SimBench.DATA_DIR_ENV) to enable."
        else
            SimBench.reset_data_dir!()
            t = SimBench.read_tables(SimBench.scenario_path(0); nrows = 1)

            # 105615 nodes, of which 70408 are auxiliary; promoting the 2380 that carry
            # two switches leaves 37587 real buses.
            @test length(SimBench.multi_switch_aux_nodes(t[:Node], t[:Switch])) == 2380
            uncollapsed = SimBench.resolve_topology(t; collapse = false)
            @test length(uncollapsed.buses) == 37587
            @test length(uncollapsed.bus_switches) == 5483

            # Every node of the table, auxiliary ones included, resolves to a bus.
            @test length(uncollapsed.bus_of) == nrow(t[:Node])

            collapsed = SimBench.resolve_topology(t)
            @test length(collapsed.buses) == 34479
            # Respecting the open selectors keeps a few station busbars apart.
            @test length(
                SimBench.resolve_topology(t; respect_open_switches = true).buses
            ) == 34498

            # 209 lines lose a closed path to their bus; no transformer does.
            @test count(!, collapsed.line_closed) == 209
            @test count(!, collapsed.trafo_closed) == 0
            @test length(collapsed.line_closed) == nrow(t[:Line])
            @test length(collapsed.trafo_closed) == nrow(t[:Transformer])

            s = sprint(show, MIME("text/plain"), collapsed)
            @test occursin("34479 buses", s)
            @test occursin("auxiliary nodes promoted: 2380", s)
        end
    end
end
