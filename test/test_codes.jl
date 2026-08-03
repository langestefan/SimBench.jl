@testset "codes" begin
    @testset "parsing" begin
        c = SimBench.SimBenchCode("1-MVLV-urban-all-0-sw")
        @test c.version == 1
        @test c.hv_level == "MV"
        @test c.lv_level == "LV"
        @test c.hv_type == "urban"
        @test c.lv_grid == "all"
        @test c.scenario == 0
        @test c.breaker_rep

        # Single voltage level: the lower level and grid fields are empty.
        c = SimBench.SimBenchCode("1-MV-rural--2-no_sw")
        @test c.hv_level == "MV"
        @test c.lv_level == ""
        @test c.lv_grid == ""
        @test c.scenario == 2
        @test !c.breaker_rep

        # "EHV" must not be split after the first "V" of a longer prefix.
        c = SimBench.SimBenchCode("1-EHVHV-mixed-1-0-sw")
        @test c.hv_level == "EHV"
        @test c.lv_level == "HV"
        @test c.lv_grid == "1"

        # The fully interconnected grid keeps all three lower levels in one field.
        c = SimBench.SimBenchCode("1-EHVHVMVLV-mixed-all-1-sw")
        @test c.hv_level == "EHV"
        @test c.lv_level == "HVMVLV"

        # The complete dataset is not a voltage level.
        c = SimBench.SimBenchCode("1-complete_data-mixed-all-0-sw")
        @test c.hv_level == "complete_data"
        @test c.lv_level == ""
        @test SimBench.is_complete_data(c)
        @test !SimBench.is_complete_data(SimBench.SimBenchCode("1-MV-urban--0-sw"))

        @test SimBench.SimBenchCode(c) === c
    end

    @testset "malformed codes" begin
        @test_throws ArgumentError SimBench.SimBenchCode("1-MVLV-urban-all-0")
        @test_throws ArgumentError SimBench.SimBenchCode("1-MVLV-urban-all-0-sw-extra")
        @test_throws ArgumentError SimBench.SimBenchCode("x-MVLV-urban-all-0-sw")
        @test_throws ArgumentError SimBench.SimBenchCode("1-MVLV-urban-all-x-sw")
        @test_throws ArgumentError SimBench.SimBenchCode("1-MXLX-urban-all-0-sw")
    end

    @testset "rendering" begin
        for code in (
                "1-MVLV-urban-all-0-sw",
                "1-MV-rural--2-no_sw",
                "1-EHVHVMVLV-mixed-all-1-sw",
                "1-complete_data-mixed-all-0-sw",
                "1-LV-rural3--1-no_sw",
            )
            @test string(SimBench.SimBenchCode(code)) == code
        end

        @test sprint(show, SimBench.SimBenchCode("1-MV-urban--0-sw")) ==
            "SimBenchCode(\"1-MV-urban--0-sw\")"

        @test string(SimBench.complete_data_code(1)) ==
            "1-complete_data-mixed-all-1-sw"
        @test string(SimBench.complete_grid_code(2)) ==
            "1-EHVHVMVLV-mixed-all-2-sw"
    end

    @testset "enumeration" begin
        all_codes = SimBench.all_simbench_codes()
        # Cross-checked against the reference implementation's
        # collect_all_simbench_codes(), which yields the same 246 codes in the same order.
        @test length(all_codes) == 246
        @test allunique(all_codes)
        @test length(SimBench.all_simbench_codes(all_data = false)) == 240

        # Every generated code must survive a parse/render round trip.
        @test all(string(SimBench.SimBenchCode(c)) == c for c in all_codes)

        # The complete-dataset and complete-grid codes lead, one pair per scenario.
        @test all_codes[1:3] ==
            ["1-complete_data-mixed-all-$(s)-sw" for s in 0:2]
        @test all_codes[4:6] ==
            ["1-EHVHVMVLV-mixed-all-$(s)-sw" for s in 0:2]

        @test length(SimBench.all_simbench_codes(hv_level = "EHV", all_data = false)) == 24
        @test length(SimBench.all_simbench_codes(hv_level = "LV", all_data = false)) == 36
        @test length(
            SimBench.all_simbench_codes(breaker_rep = "no_sw", all_data = false)
        ) == 120
        @test length(
            SimBench.all_simbench_codes(
                hv_level = "HV", hv_type = "urban", scenario = 1, all_data = false
            )
        ) == 10

        @test SimBench.all_simbench_codes(
            hv_level = "MV", lv_level = "", hv_type = "urban", scenario = 0,
            all_data = false,
        ) == ["1-MV-urban--0-sw", "1-MV-urban--0-no_sw"]

        # Filters compose: every result honours every constraint.
        mv = SimBench.all_simbench_codes(
            hv_level = "MV", scenario = 2, breaker_rep = "sw", all_data = false
        )
        @test !isempty(mv)
        for c in SimBench.SimBenchCode.(mv)
            @test c.hv_level == "MV"
            @test c.scenario == 2
            @test c.breaker_rep
        end

        # The shortened variant differs only in its lower-level grid numbering.
        short = SimBench.all_simbench_codes(shortened = true)
        @test length(short) == length(all_codes)
        @test short != all_codes
    end
end
