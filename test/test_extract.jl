using DataFrames: DataFrame, eachrow, nrow

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
        if DATASET === nothing
            @info "Skipping extraction tests: dataset unavailable."
        elseif !have_reference("extractions.csv")
            @info "Skipping extraction tests: reference fixture missing."
        else
            SimBench.reset_data_dir!()
            # Read each scenario once and extract from it, rather than re-reading per code.
            by_scenario = Dict(
                s => SimBench.read_tables(SimBench.scenario_path(s); nrows = 1)
                    for s in (0, 1, 2)
            )

            # Row counts and element ids, as the reference implementation's
            # get_extracted_csv_data produces them. Equal counts do not mean equal
            # elements, which is why the ids are digested too. Two digests: one over the
            # ids in table order and one over them sorted, so a failure says whether the
            # elements differ or only their order does.
            expected = read_reference("extractions.csv")
            for code in unique(expected.code)
                c = SimBench.SimBenchCode(code)
                extracted = SimBench.extract_tables(by_scenario[c.scenario], c)
                for r in eachrow(expected[expected.code .== code, :])
                    table = extracted[Symbol(r.table)]
                    @test nrow(table) == r.nrows
                    ids = string.(skipmissing(table.id))
                    @test id_digest(ids) == r.id_digest
                    @test id_digest(sort(ids)) == r.id_digest_sorted
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
