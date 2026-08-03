using DataFrames: nrow

@testset "grid" begin
    @testset "unsupported codes" begin
        # Extraction of individual grids is not implemented, so those codes are refused
        # with a message pointing at the complete_data alternative.
        err = try
            SimBench.read_grid("1-MVLV-urban-all-0-sw")
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("not implemented yet", err.msg)
        @test occursin("1-complete_data-mixed-all-0-sw", err.msg)

        @test_throws ArgumentError SimBench.read_grid("1-EHVHVMVLV-mixed-all-0-sw")
    end

    @testset "reading" begin
        configured = get(ENV, SimBench.DATA_DIR_ENV, nothing)
        if configured === nothing || !isdir(configured)
            @info "Skipping grid reading tests: set $(SimBench.DATA_DIR_ENV) to enable."
        else
            SimBench.reset_data_dir!()

            # Reading by scenario number and by code agree.
            grid = SimBench.read_grid(0; nrows = 4)
            @test grid.code == SimBench.complete_data_code(0)
            @test SimBench.scenario(grid) == 0
            @test SimBench.read_grid("1-complete_data-mixed-all-0-sw"; nrows = 4).code ==
                grid.code

            # Every table of the format is present, empty ones included.
            @test sort(collect(keys(grid))) == sort(collect(SimBench.ALL_TABLES))
            for t in SimBench.ALL_TABLES
                @test haskey(grid, t)
            end

            @test nrow(grid[:Node]) == 105615
            @test nrow(grid[:Line]) == 34606
            @test nrow(grid[:Switch]) == 73511
            @test_throws KeyError grid[:NotATable]

            # nrows applies to the profile tables only.
            @test nrow(grid[:LoadProfile]) == 4
            @test nrow(grid[:Load]) == 36063

            # Scenario 0 ships no storage; scenario 2 does.
            @test nrow(grid[:Storage]) == 0
            @test nrow(SimBench.read_grid(2; nrows = 1)[:Storage]) == 6533

            # Nominal voltages span all four levels, and every bus sits within one.
            levels = unique(
                SimBench.voltlvl_from_vn_kv.(skipmissing(grid[:Node].vmR))
            )
            @test sort(levels) == [1, 3, 5, 7]

            # show reports the code and the populated tables.
            s = sprint(show, MIME("text/plain"), grid)
            @test occursin("1-complete_data-mixed-all-0-sw", s)
            @test occursin("Node", s)
            @test occursin("105615 rows", s)
            @test occursin("empty tables", s)
            @test sprint(show, grid) ==
                "SimBenchGrid(\"1-complete_data-mixed-all-0-sw\")"
        end
    end
end
