"""Create a dataset folder for `scenario` under `root`, containing `tables` as empty files."""
function make_scenario_dir(root, scenario; tables = SimBench.REQUIRED_TABLES)
    dir = joinpath(root, SimBench.complete_data_folder(scenario))
    mkpath(dir)
    for t in tables
        touch(joinpath(dir, SimBench.csv_filename(t)))
    end
    return dir
end

@testset "data_source" begin
    # Every test in this file mutates process-global state; always hand it back.
    SimBench.reset_data_dir!()

    @testset "folder naming" begin
        @test SimBench.complete_data_folder(0) ==
            "1-complete_data-mixed-all-0-sw"
        @test SimBench.complete_data_folder(2) ==
            "1-complete_data-mixed-all-2-sw"
        @test SimBench.complete_data_folder(0; version = 2) ==
            "2-complete_data-mixed-all-0-sw"
    end

    @testset "resolution" begin
        mktempdir() do root
            withenv(SimBench.DATA_DIR_ENV => nothing) do
                SimBench.reset_data_dir!()
                @test_throws SimBench.SimBenchDataError SimBench.data_dir()

                # Explicit setting wins.
                @test SimBench.set_data_dir!(root) == abspath(root)
                @test SimBench.data_dir() == abspath(root)
                SimBench.reset_data_dir!()
                @test_throws SimBench.SimBenchDataError SimBench.data_dir()
            end

            # Environment variable is the fallback.
            withenv(SimBench.DATA_DIR_ENV => root) do
                SimBench.reset_data_dir!()
                @test SimBench.data_dir() == abspath(root)

                # ...and set_data_dir! takes precedence over it.
                other = mktempdir()
                SimBench.set_data_dir!(other)
                @test SimBench.data_dir() == abspath(other)
                SimBench.reset_data_dir!()
                @test SimBench.data_dir() == abspath(root)
            end

            withenv(SimBench.DATA_DIR_ENV => joinpath(root, "nope")) do
                SimBench.reset_data_dir!()
                @test_throws SimBench.SimBenchDataError SimBench.data_dir()
            end
        end
        SimBench.reset_data_dir!()

        @test_throws SimBench.SimBenchDataError SimBench.set_data_dir!(
            "/definitely/not/here",
        )
    end

    @testset "table discovery" begin
        mktempdir() do root
            dir = make_scenario_dir(root, 0)
            @test isempty(SimBench.missing_tables(dir))
            # Optional tables were not created, so they must not show up as available.
            @test sort(SimBench.available_tables(dir)) ==
                sort(collect(SimBench.REQUIRED_TABLES))

            rm(joinpath(dir, SimBench.csv_filename(:Node)))
            rm(joinpath(dir, SimBench.csv_filename(:LineType)))
            @test sort(SimBench.missing_tables(dir)) == sort([:LineType, :Node])

            # An optional table present on disk is reported as available.
            touch(joinpath(dir, SimBench.csv_filename(:Storage)))
            @test :Storage in SimBench.available_tables(dir)
            @test isempty(
                intersect(SimBench.missing_tables(dir), (:Storage,)),
            )
        end
    end

    @testset "scenario_path" begin
        mktempdir() do root
            make_scenario_dir(root, 0)
            make_scenario_dir(root, 1; tables = (:Node, :Load))

            SimBench.set_data_dir!(root)
            try
                @test SimBench.scenario_path(0) ==
                    joinpath(abspath(root), SimBench.complete_data_folder(0))

                # Present but incomplete.
                err = try
                    SimBench.scenario_path(1)
                    nothing
                catch e
                    e
                end
                @test err isa SimBench.SimBenchDataError
                @test occursin("missing required tables", err.msg)

                # Absent entirely.
                @test_throws SimBench.SimBenchDataError SimBench.scenario_path(2)

                # Not a published scenario.
                @test_throws ArgumentError SimBench.scenario_path(7)
                @test_throws ArgumentError SimBench.scenario_path(-1)
            finally
                SimBench.reset_data_dir!()
            end
        end
    end

    @testset "real dataset" begin
        configured = get(ENV, SimBench.DATA_DIR_ENV, nothing)
        if configured === nothing || !isdir(configured)
            @info "Skipping real-dataset tests: set $(SimBench.DATA_DIR_ENV) to enable."
        else
            SimBench.reset_data_dir!()
            for scenario in SimBench.SCENARIOS
                path = SimBench.scenario_path(scenario)
                available = SimBench.available_tables(path)
                @test isdir(path)
                @test isempty(SimBench.missing_tables(path))

                # No published scenario ships these.
                for t in SimBench.UNUSED_TABLES
                    @test !(t in available)
                end

                # Storage and HVDC appear only in the future scenarios.
                for t in SimBench.SCENARIO_TABLES
                    @test (t in available) == (scenario != 0)
                end
            end
        end
    end

    SimBench.reset_data_dir!()
end
