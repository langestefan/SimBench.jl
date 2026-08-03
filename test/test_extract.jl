using DataFrames: DataFrame, nrow

# Row counts produced by the reference implementation's get_extracted_csv_data, captured
# by running upstream's own extract_simbench_grids_from_csv with pandapower stubbed out.
# The Julia port was additionally checked to produce the same set of element ids, not
# just the same counts, for every code below.
const REFERENCE_EXTRACTIONS = Dict(
    "1-LV-rural1--0-sw" => Dict(
        :Node => 43, :Line => 13, :Load => 13, :Switch => 28, :Transformer => 1,
        :ExternalNet => 1, :RES => 4, :PowerPlant => 0, :Coordinates => 17,
        :Measurement => 0, :Substation => 0,
    ),
    "1-LV-rural1--0-no_sw" => Dict(
        :Node => 43, :Line => 13, :Load => 13, :Switch => 28, :Transformer => 1,
        :ExternalNet => 1, :RES => 4,
    ),
    "1-LV-urban6--0-sw" => Dict(
        :Node => 175, :Line => 57, :Load => 111, :Switch => 116, :Transformer => 1,
        :ExternalNet => 1, :RES => 5, :Coordinates => 61,
    ),
    "1-LV-semiurb4--2-sw" => Dict(
        :Node => 130, :Line => 42, :Load => 58, :Switch => 86, :Transformer => 1,
        :ExternalNet => 1, :RES => 6, :Measurement => 3,
    ),
    "1-MV-rural--0-sw" => Dict(
        :Node => 299, :Line => 99, :Load => 96, :Switch => 204, :Transformer => 2,
        :ExternalNet => 1, :RES => 102, :Coordinates => 276, :Measurement => 37,
        :Substation => 1,
    ),
    "1-MV-comm--0-no_sw" => Dict(
        :Node => 329, :Line => 109, :Load => 98, :Switch => 226, :Transformer => 2,
        :ExternalNet => 1, :RES => 89,
    ),
    "1-MV-urban--1-sw" => Dict(
        :Node => 440, :Line => 147, :Load => 139, :Switch => 305, :Transformer => 2,
        :ExternalNet => 1, :RES => 134,
    ),
    "1-MVLV-rural-1.108-0-sw" => Dict(
        :Node => 341, :Line => 112, :Load => 108, :Switch => 232, :Transformer => 3,
        :ExternalNet => 1, :RES => 105,
    ),
    "1-MVLV-urban-all-0-sw" => Dict(
        :Node => 31382, :Line => 10328, :Load => 11542, :Switch => 20933,
        :Transformer => 135, :ExternalNet => 1, :RES => 806, :Substation => 2,
    ),
    "1-MVLV-comm-all-2-sw" => Dict(
        :Node => 18630, :Line => 6133, :Load => 8637, :Switch => 12424,
        :Transformer => 81, :ExternalNet => 1, :RES => 964,
    ),
    "1-HV-mixed--0-sw" => Dict(
        :Node => 308, :Line => 95, :Load => 58, :Switch => 422, :Transformer => 6,
        :ExternalNet => 3, :RES => 103, :PowerPlant => 0, :Substation => 18,
    ),
    "1-HV-urban--0-sw" => Dict(
        :Node => 372, :Line => 113, :Load => 79, :Switch => 498, :Transformer => 3,
        :ExternalNet => 1, :RES => 98,
    ),
    "1-HVMV-mixed-all-0-sw" => Dict(
        :Node => 5408, :Line => 1800, :Load => 1686, :Switch => 3924,
        :Transformer => 36, :ExternalNet => 3, :RES => 1773,
    ),
    "1-HVMV-urban-2.203-0-sw" => Dict(
        :Node => 733, :Line => 234, :Load => 194, :Switch => 745, :Transformer => 5,
        :ExternalNet => 1, :RES => 219,
    ),
    "1-EHV-mixed--0-sw" => Dict(
        :Node => 3087, :Line => 849, :Load => 390, :Switch => 4500,
        :Transformer => 209, :ExternalNet => 0, :RES => 225, :PowerPlant => 345,
    ),
    "1-EHVHV-mixed-1-0-sw" => Dict(
        :Node => 3389, :Line => 944, :Load => 445, :Switch => 4919,
        :Transformer => 215, :ExternalNet => 0, :RES => 325, :PowerPlant => 345,
    ),
    "1-EHVHV-mixed-all-0-sw" => Dict(
        :Node => 3759, :Line => 1057, :Load => 523, :Switch => 5416,
        :Transformer => 218, :ExternalNet => 0, :RES => 422, :PowerPlant => 345,
    ),
    "1-EHVHVMVLV-mixed-all-0-sw" => Dict(
        :Node => 105615, :Line => 34606, :Load => 35647, :Switch => 73511,
        :Transformer => 686, :ExternalNet => 0, :RES => 5734, :PowerPlant => 345,
        :Substation => 41,
    ),
)

@testset "extract" begin
    @testset "subnet naming" begin
        @test SimBench.hv_subnet_of("EHV", "mixed") == ("EHV1", 1)
        @test SimBench.hv_subnet_of("HV", "mixed") == ("HV1", 1)
        @test SimBench.hv_subnet_of("HV", "urban") == ("HV2", 2)
        @test SimBench.hv_subnet_of("MV", "rural") == ("MV1.101", 1)
        @test SimBench.hv_subnet_of("MV", "comm") == ("MV4.101", 4)
        @test SimBench.hv_subnet_of("LV", "rural1") == ("LV1.101", 1)

        # The two LV grids supplied by the second MV grid are numbered from .201.
        @test SimBench.hv_subnet_of("LV", "semiurb5") == ("LV5.201", 5)
        @test SimBench.hv_subnet_of("LV", "urban6") == ("LV6.201", 6)

        @test SimBench.hv_subnet_of(SimBench.SimBenchCode("1-MVLV-urban-all-0-sw")) ==
            ("MV3.101", 3)

        @test_throws ArgumentError SimBench.hv_subnet_of("XV", "mixed")
        @test_throws ArgumentError SimBench.hv_subnet_of("MV", "nope")
    end

    @testset "high-voltage lower grids" begin
        empty_load = SimBench.empty_table(:Load)
        # HV grids are fixed rather than derived from the Load table.
        @test SimBench.lv_subnets_of("HV", "all", "EHV1", 1, empty_load) ==
            ["HV1", "HV2"]
        @test SimBench.lv_subnets_of("HV", "1", "EHV1", 1, empty_load) == ["HV1"]
        @test SimBench.lv_subnets_of("HV", "2", "EHV1", 1, empty_load) == ["HV2"]
        @test_throws ArgumentError SimBench.lv_subnets_of(
            "HV", "3", "EHV1", 1, empty_load
        )

        # A single-level code selects no lower grids at all.
        @test SimBench.lv_subnets_of("", "", "MV1.101", 1, empty_load) == String[]
    end

    @testset "lower grids from equivalent loads" begin
        # Each lower grid shows up as one equivalent load whose profile names its
        # character, so three lv_rural1 loads mean three LV1 grids.
        load = DataFrame(
            subnet = [
                "MV1.101_LV", "MV1.101_LV", "MV1.101_LV", "MV1.101_LV",
                "MV1.101", "MV2.101_LV",
            ],
            profile = ["lv_rural1", "lv_rural1", "lv_rural1", "lv_rural2", "H0-A", "lv_rural1"],
        )
        subnets = SimBench.lv_subnets_of("LV", "all", "MV1.101", 1, load)
        @test sort(subnets) == ["LV1.101", "LV1.102", "LV1.103", "LV2.101"]

        # Numbering is offset by the supplying grid's number.
        load2 = DataFrame(
            subnet = ["MV2.101_LV", "MV2.101_LV"], profile = ["lv_urban6", "lv_urban6"]
        )
        @test sort(SimBench.lv_subnets_of("LV", "all", "MV2.101", 2, load2)) ==
            ["LV6.201", "LV6.202"]

        # Selecting one grid by name.
        @test SimBench.lv_subnets_of("LV", "1.102", "MV1.101", 1, load) == ["LV1.102"]
        @test_throws ArgumentError SimBench.lv_subnets_of(
            "LV", "9.999", "MV1.101", 1, load
        )
    end

    @testset "bus-bus switches" begin
        node = DataFrame(
            id = ["b1", "b2", "aux1", "aux2"],
            type = ["busbar", "busbar", "auxiliary", "auxiliary"],
        )
        switch = DataFrame(
            id = ["s_bus_bus", "s_branch", "s_branch2"],
            nodeA = ["b1", "b1", "aux1"],
            nodeB = ["b2", "aux1", "b2"],
        )
        # Only the switch with two ordinary endpoints counts as bus-bus.
        @test SimBench.bus_bus_switch_rows(switch, node) == Set([1])

        # An endpoint that is not a node at all is an error.
        bad = DataFrame(id = ["s"], nodeA = ["b1"], nodeB = ["nowhere"])
        @test_throws ArgumentError SimBench.bus_bus_switch_rows(bad, node)

        # So is a switch between two auxiliary nodes.
        double_aux = DataFrame(id = ["s"], nodeA = ["aux1"], nodeB = ["aux2"])
        @test_throws ArgumentError SimBench.bus_bus_switch_rows(double_aux, node)
    end

    @testset "table filtering" begin
        line = DataFrame(
            id = ["inside", "other_grid", "coupling", "reverse_coupling"],
            subnet = ["MV1.101", "MV9.999", "MV1.101_LV1.101", "LV1.101_MV1.101"],
        )
        # The plain element is kept; the foreign one is dropped; the two coupling
        # elements are dropped because the grid they stand in for is itself selected.
        kept = SimBench.extract_table(line, :Line, ["MV1.101"], ["LV1.101"])
        @test kept.id == ["inside"]

        # With the lower grid not selected, the coupling element is the equivalent that
        # represents it, so it stays.
        kept = SimBench.extract_table(line, :Line, ["MV1.101"], String[])
        @test sort(kept.id) == ["coupling", "inside"]

        # complete_data keeps everything, untouched.
        @test SimBench.extract_table(line, :Line, ["complete_data"], String[]) === line

        # Tables without a subnet column pass through.
        prof = DataFrame(time = 1:3, x = [1.0, 2.0, 3.0])
        @test SimBench.extract_table(prof, :LoadProfile, ["MV1.101"], String[]) === prof
    end

    @testset "against the reference implementation" begin
        configured = get(ENV, SimBench.DATA_DIR_ENV, nothing)
        if configured === nothing || !isdir(configured)
            @info "Skipping extraction tests: set $(SimBench.DATA_DIR_ENV) to enable."
        else
            SimBench.reset_data_dir!()
            # Read each scenario once and extract from it, rather than re-reading per code.
            by_scenario = Dict(
                s => SimBench.read_tables(SimBench.scenario_path(s); nrows = 1)
                for s in (0, 1, 2)
            )

            for (code, expected) in REFERENCE_EXTRACTIONS
                c = SimBench.SimBenchCode(code)
                extracted = SimBench.extract_tables(by_scenario[c.scenario], c)
                for (table, rows) in expected
                    @test nrow(extracted[table]) == rows
                end
            end

            # Extraction ignores the switch flag; that variant is applied afterwards.
            t0 = by_scenario[0]
            sw = SimBench.extract_tables(t0, SimBench.SimBenchCode("1-LV-rural1--0-sw"))
            no_sw = SimBench.extract_tables(
                t0, SimBench.SimBenchCode("1-LV-rural1--0-no_sw")
            )
            @test nrow(sw[:Node]) == nrow(no_sw[:Node])
            @test sw[:Switch].id == no_sw[:Switch].id

            # The complete grid holds every node of the dataset, but drops the
            # equivalents that stand in for grids now included in full.
            complete = SimBench.extract_tables(
                t0, SimBench.SimBenchCode("1-EHVHVMVLV-mixed-all-0-sw")
            )
            @test nrow(complete[:Node]) == nrow(t0[:Node])
            @test nrow(complete[:ExternalNet]) == 0
            @test nrow(complete[:Load]) < nrow(t0[:Load])

            # read_grid wires extraction in.
            grid = SimBench.read_grid("1-MV-rural--0-sw"; nrows = 1)
            @test nrow(grid[:Node]) == 299
            @test grid.code == SimBench.SimBenchCode("1-MV-rural--0-sw")
        end
    end
end
