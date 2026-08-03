using DataFrames: DataFrame, nrow, ncol, propertynames
using Dates: DateTime, Minute

"""Write `lines` as `table`'s CSV file inside `dir`."""
function write_csv(dir, table, lines)
    path = joinpath(dir, SimBench.csv_filename(table))
    open(path, "w") do io
        for l in lines
            println(io, l)
        end
    end
    return path
end

const NODE_HEADER = "id;type;vmSetp;vaSetp;vmR;vmMin;vmMax;substation;coordID;subnet;voltLvl"

@testset "io" begin
    @testset "empty tables" begin
        node = SimBench.empty_table(:Node)
        @test nrow(node) == 0
        @test propertynames(node) == SimBench.table_columns(:Node)
        @test eltype(node.vmSetp) == Union{Missing, Float64}
        @test eltype(node.voltLvl) == Union{Missing, Int}
        @test eltype(node.id) == Union{Missing, String}

        # Profile tables have no fixed schema, so only the time column is known.
        prof = SimBench.empty_table(:LoadProfile)
        @test nrow(prof) == 0
        @test propertynames(prof) == [:time]
        @test eltype(prof.time) == DateTime
    end

    @testset "fixed tables" begin
        mktempdir() do dir
            write_csv(
                dir, :Node,
                [
                    NODE_HEADER,
                    "MV1.1 bus;busbar;1.025;NULL;20;0.965;1.055;Sub1;coord_1;MV1.1;5",
                    "MV1.2 bus;auxiliary;NULL;0.0;20;0.9;1.1;NULL;NULL;MV1.1;5",
                ],
            )
            df = SimBench.read_table(dir, :Node)
            @test nrow(df) == 2
            @test propertynames(df) == SimBench.table_columns(:Node)

            # NULL becomes missing, in string and numeric columns alike.
            @test ismissing(df.vaSetp[1])
            @test ismissing(df.vmSetp[2])
            @test ismissing(df.substation[2])
            @test df.vmSetp[1] == 1.025
            @test df.voltLvl == [5, 5]
            @test df.id[1] == "MV1.1 bus"

            # Element types follow the schema, not the data: vmR has no NULL here but
            # is still typed as if it could.
            @test eltype(df.vmR) == Union{Missing, Float64}
            @test eltype(df.voltLvl) == Union{Missing, Int}
        end
    end

    @testset "absent files" begin
        mktempdir() do dir
            df = SimBench.read_table(dir, :Storage)
            @test nrow(df) == 0
            @test propertynames(df) == SimBench.table_columns(:Storage)

            tabs = SimBench.read_tables(dir, [:Node, :Storage, :LoadProfile])
            @test sort(collect(keys(tabs))) == [:LoadProfile, :Node, :Storage]
            @test all(nrow(v) == 0 for v in values(tabs))
        end
    end

    @testset "header validation" begin
        mktempdir() do dir
            # A column is missing from the header.
            write_csv(dir, :Node, ["id;type;vmSetp", "a;busbar;1.0"])
            err = try
                SimBench.read_table(dir, :Node)
                nothing
            catch e
                e
            end
            @test err isa ArgumentError
            @test occursin("does not match the Node schema", err.msg)
            @test occursin("missing columns", err.msg)

            # strict=false accepts whatever the file contains.
            df = SimBench.read_table(dir, :Node; strict = false)
            @test propertynames(df) == [:id, :type, :vmSetp]

            # Right columns, wrong order is still a mismatch.
            write_csv(
                dir, :Substation, ["subnet;id;voltLvl", "MV1.1;Sub1;5"],
            )
            @test_throws ArgumentError SimBench.read_table(dir, :Substation)
        end
    end

    @testset "profile tables" begin
        mktempdir() do dir
            write_csv(
                dir, :LoadProfile,
                [
                    "time;H0-A_pload;H0-A_qload",
                    "01.01.2016 00:00;0.1;0.02",
                    "01.01.2016 00:15;0.2;0.04",
                    "31.12.2016 23:45;0.3;0.06",
                ],
            )
            df = SimBench.read_table(dir, :LoadProfile)
            @test nrow(df) == 3
            @test propertynames(df) == [:time, Symbol("H0-A_pload"), Symbol("H0-A_qload")]
            @test eltype(df.time) == DateTime
            @test df.time[1] == DateTime(2016, 1, 1, 0, 0)
            @test df.time[2] == DateTime(2016, 1, 1, 0, 15)
            @test df.time[3] == DateTime(2016, 12, 31, 23, 45)
            @test df[!, Symbol("H0-A_pload")] == [0.1, 0.2, 0.3]
            @test eltype(df[!, Symbol("H0-A_qload")]) == Float64

            # nrows caps the number of data rows read.
            @test nrow(SimBench.read_table(dir, :LoadProfile; nrows = 2)) == 2
            @test nrow(SimBench.read_table(dir, :LoadProfile; nrows = 99)) == 3
        end
    end

    @testset "real dataset" begin
        configured = get(ENV, SimBench.DATA_DIR_ENV, nothing)
        if configured === nothing || !isdir(configured)
            @info "Skipping real-dataset io tests: set $(SimBench.DATA_DIR_ENV) to enable."
        else
            SimBench.reset_data_dir!()
            dir = SimBench.scenario_path(0)

            # Row counts are fixed by the published dataset.
            expected = Dict(
                :Node => 105615, :Line => 34606, :Load => 36063, :RES => 6150,
                :Switch => 73511, :Transformer => 686, :ExternalNet => 444,
                :PowerPlant => 345, :Substation => 41, :StudyCases => 24,
                :LoadProfile => 35136, :RESProfile => 35136,
                :PowerPlantProfile => 35136,
            )
            for (table, n) in expected
                df = SimBench.read_table(dir, table)
                @test nrow(df) == n
                if SimBench.has_fixed_schema(table)
                    @test propertynames(df) == SimBench.table_columns(table)
                end
            end

            # Scenario 0 ships no storage or HVDC, and reading them yields empty tables.
            for table in SimBench.SCENARIO_TABLES
                @test nrow(SimBench.read_table(dir, table)) == 0
            end

            # Scenario 2 does.
            dir2 = SimBench.scenario_path(2)
            @test nrow(SimBench.read_table(dir2, :Storage)) == 6533
            @test nrow(SimBench.read_table(dir2, :DCLineType)) == 2
            @test nrow(SimBench.read_table(dir2, :StorageProfile)) == 35136

            # A full year of 2016 at 96 quarter-hours per day.
            prof = SimBench.read_table(dir, :LoadProfile)
            @test nrow(prof) == 366 * 96
            @test prof.time[1] == DateTime(2016, 1, 1, 0, 0)
            @test prof.time[end] == DateTime(2016, 12, 31, 23, 45)

            # Timestamps are local wall-clock time, so the two daylight-saving
            # transitions break both monotonicity and uniform spacing. The row index,
            # not the timestamp, is the uniform quarter-hour sequence.
            @test !issorted(prof.time)
            steps = findall(
                i -> prof.time[i + 1] - prof.time[i] != Minute(15),
                1:(nrow(prof) - 1),
            )
            @test length(steps) == 2
            @test prof.time[steps[1]] == DateTime(2016, 3, 27, 1, 45)
            @test prof.time[steps[1] + 1] == DateTime(2016, 3, 27, 3, 0)
            @test prof.time[steps[2]] == DateTime(2016, 10, 30, 2, 45)
            @test prof.time[steps[2] + 1] == DateTime(2016, 10, 30, 2, 0)
            @test length(unique(prof.time)) == nrow(prof) - 4

            # Identifiers are always present.
            for table in (:Node, :Line, :Load, :Switch, :Transformer)
                @test !any(ismissing, SimBench.read_table(dir, table).id)
            end
        end
    end
end
