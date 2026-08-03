@testset "schema" begin
    @testset "table groups" begin
        @test SimBench.csv_tablenames(:types) ==
            [:LineType, :DCLineType, :TransformerType, :Transformer3WType]
        @test SimBench.csv_tablenames(:cases) == [:StudyCases]
        @test length(SimBench.csv_tablenames(:elements)) == 14
        @test length(SimBench.csv_tablenames(:profiles)) == 4

        # Multiple groups concatenate in the order given.
        @test SimBench.csv_tablenames((:cases, :res_elements)) ==
            [:StudyCases, :NodePFResult]
        @test SimBench.csv_tablenames((:res_elements, :cases)) ==
            [:NodePFResult, :StudyCases]

        @test_throws ArgumentError SimBench.csv_tablenames(:nope)
    end

    @testset "table inventory" begin
        # 14 elements + 4 profiles + 4 types + 1 case + 1 result
        @test length(SimBench.ALL_TABLES) == 24
        @test allunique(SimBench.ALL_TABLES)

        # REQUIRED / SCENARIO / UNUSED partition ALL_TABLES exactly.
        @test length(SimBench.REQUIRED_TABLES) == 17
        @test length(SimBench.SCENARIO_TABLES) == 3
        @test length(SimBench.UNUSED_TABLES) == 4
        parts = vcat(
            collect(SimBench.REQUIRED_TABLES),
            collect(SimBench.SCENARIO_TABLES),
            collect(SimBench.UNUSED_TABLES),
        )
        @test allunique(parts)
        @test sort(parts) == sort(collect(SimBench.ALL_TABLES))

        @test sort(collect(SimBench.REQUIRED_TABLES)) ==
            sort(setdiff(SimBench.ALL_TABLES, SimBench.OPTIONAL_TABLES))
        @test isempty(
            intersect(SimBench.REQUIRED_TABLES, SimBench.OPTIONAL_TABLES),
        )

        # Upstream treats these two as mandatory; so do we.
        @test :Node in SimBench.REQUIRED_TABLES
        @test :Load in SimBench.REQUIRED_TABLES

        # Shipped by scenarios 1 and 2 only.
        for t in (:Storage, :StorageProfile, :DCLineType)
            @test t in SimBench.SCENARIO_TABLES
        end

        # In the format, in no published scenario.
        for t in (:Shunt, :Transformer3W, :Transformer3WType, :NodePFResult)
            @test t in SimBench.UNUSED_TABLES
        end
    end

    @testset "filenames" begin
        @test SimBench.csv_filename(:Node) == "Node.csv"
        @test SimBench.csv_filename(:TransformerType) == "TransformerType.csv"
        @test SimBench.table_path("/data/grid", :Line) ==
            joinpath("/data/grid", "Line.csv")
    end
end
