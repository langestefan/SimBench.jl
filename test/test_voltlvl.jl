@testset "voltlvl" begin
    @testset "names and numbers" begin
        @test SimBench.voltlvl_int("EHV") == 1
        @test SimBench.voltlvl_int("HV") == 3
        @test SimBench.voltlvl_int("MV") == 5
        @test SimBench.voltlvl_int("LV") == 7

        # Boundary levels, in both spellings and either case.
        @test SimBench.voltlvl_int("EHV-HV") == 2
        @test SimBench.voltlvl_int("EHVHV") == 2
        @test SimBench.voltlvl_int("hv-mv") == 4
        @test SimBench.voltlvl_int("HVMV") == 4
        @test SimBench.voltlvl_int("mvlv") == 6

        # UHV is an accepted alias for EHV.
        @test SimBench.voltlvl_int("UHV") == 1
        @test SimBench.voltlvl_int("uhv-hv") == 2

        # Numbers pass through, as strings too.
        @test SimBench.voltlvl_int(5) == 5
        @test SimBench.voltlvl_int("5") == 5

        @test SimBench.voltlvl_name(5) == "MV"
        @test SimBench.voltlvl_name("mv") == "MV"
        @test SimBench.voltlvl_name(2) == "EHV-HV"
        @test [SimBench.voltlvl_name(i) for i in 1:7] ==
            collect(SimBench.VOLTLVL_NAMES)

        # Round trip over the whole range.
        @test all(SimBench.voltlvl_int(SimBench.voltlvl_name(i)) == i for i in 1:7)

        @test_throws ArgumentError SimBench.voltlvl_int("nope")
        @test_throws ArgumentError SimBench.voltlvl_int(0)
        @test_throws ArgumentError SimBench.voltlvl_int(8)
    end

    @testset "from nominal voltage" begin
        @test SimBench.voltlvl_from_vn_kv(380.0) == 1
        @test SimBench.voltlvl_from_vn_kv(220.0) == 1
        @test SimBench.voltlvl_from_vn_kv(110.0) == 3
        @test SimBench.voltlvl_from_vn_kv(20.0) == 5
        @test SimBench.voltlvl_from_vn_kv(10.0) == 5
        @test SimBench.voltlvl_from_vn_kv(0.4) == 7

        # The bounds themselves belong to the lower level.
        @test SimBench.voltlvl_from_vn_kv(145.0) == 3
        @test SimBench.voltlvl_from_vn_kv(145.001) == 1
        @test SimBench.voltlvl_from_vn_kv(60.0) == 5
        @test SimBench.voltlvl_from_vn_kv(60.001) == 3
        @test SimBench.voltlvl_from_vn_kv(1.0) == 7
        @test SimBench.voltlvl_from_vn_kv(1.001) == 5

        # A bus is never on a boundary level.
        @test all(isodd(SimBench.voltlvl_from_vn_kv(v)) for v in (380, 110, 20, 0.4))
    end
end
