using DataFrames: nrow, ncol, names
using Dates: DateTime

@testset "profiles" begin
    if DATASET === nothing
        @info "Skipping profile tests: dataset unavailable."
    else
        grid = SimBench.read_grid("1-MV-rural--0-no_sw"; nrows = 20)

        @testset "unapplied profiles are dropped on read" begin
            applied = Set(skipmissing(grid[:Load].profile))
            expect = Set(
                [string.(applied, "_pload"); string.(applied, "_qload"); "time"]
            )
            @test Set(names(grid[:LoadProfile])) == expect

            # Every remaining renewable profile is used by some element.
            res_applied = Set(skipmissing(grid[:RES].profile))
            @test Set(names(grid[:RESProfile])) == union(res_applied, Set(["time"]))
        end

        @testset "study cases are reduced to the grid's level" begin
            sc = grid[:StudyCases]
            @test nrow(sc) == 6
            @test "voltLvl" ∉ names(sc)
            @test Set(sc[!, Symbol("Study Case")]) ==
                Set(["hL", "n1", "hW", "hPV", "lW", "lPV"])
        end

        profiles = SimBench.absolute_profiles(grid)

        @testset "absolute profiles" begin
            lp = profiles[(:Load, :pLoad)]
            @test nrow(lp) == 20
            @test ncol(lp) == nrow(grid[:Load]) + 1
            @test names(lp)[1] == "time"

            # Absolute value = relative profile times the element's base power.
            load = grid[:Load]
            for i in (1, nrow(load))
                col = string(load.profile[i], "_pload")
                @test lp[!, load.id[i]] ≈ grid[:LoadProfile][!, col] .* load.pLoad[i]
            end

            rp = profiles[(:RES, :pRES)]
            @test ncol(rp) == nrow(grid[:RES]) + 1
            @test all(≥(0), rp[3, 2:end])
        end

        @testset "apply_profile!" begin
            data = SimBench.powermodels_data(grid)
            base = data["baseMVA"]
            SimBench.apply_profile!(data, profiles, 7)

            lp, rp = profiles[(:Load, :pLoad)], profiles[(:RES, :pRES)]
            for l in values(data["load"])
                kind, id = l["source_id"]
                if kind == "load"
                    @test l["pd"] == lp[7, id] / base
                    @test l["qd"] == profiles[(:Load, :qLoad)][7, id] / base
                else
                    @test l["pd"] == -rp[7, id] / base
                end
            end

            # A DateTime picks the same row as its row number.
            t = lp[7, :time]
            again = SimBench.powermodels_data(grid)
            SimBench.apply_profile!(again, profiles, t)
            @test all(
                again["load"][k]["pd"] == data["load"][k]["pd"] for
                    k in keys(data["load"])
            )
            @test_throws ArgumentError SimBench.apply_profile!(
                again, profiles, DateTime(1999)
            )

            # Values come from the profiles, not the current state.
            SimBench.apply_profile!(data, profiles, 7)
            @test all(
                again["load"][k]["pd"] == data["load"][k]["pd"] for
                    k in keys(data["load"])
            )

            # Under pq_as = :gen the pinned generator limits move with the power.
            as_gen = SimBench.powermodels_data(grid; pq_as = :gen)
            SimBench.apply_profile!(as_gen, profiles, 7)
            for g in values(as_gen["gen"])
                g["source_id"][1] == "sgen" || continue
                @test g["pg"] == rp[7, g["source_id"][2]] / base
                @test g["pmin"] == g["pmax"] == g["pg"]
            end
        end

        @testset "apply_study_case!" begin
            data = SimBench.powermodels_data(grid)
            base = data["baseMVA"]
            load_of = Dict(
                (l["source_id"][1], l["source_id"][2]) => l for
                    l in values(data["load"])
            )

            # Low wind case: loads scaled down, renewables at their type's factor.
            SimBench.apply_study_case!(data, grid, "lW")
            load, res = grid[:Load], grid[:RES]
            @test load_of[("load", load.id[1])]["pd"] ≈ 0.1 * load.pLoad[1] / base
            @test load_of[("load", load.id[1])]["qd"] ≈
                0.122543 * load.qLoad[1] / base
            factor = Dict("Wind_MV" => 1.0, "PV_MV" => 0.8)
            for i in 1:nrow(res)
                f = get(factor, res.type[i], 1.0)
                @test load_of[("sgen", res.id[i])]["pd"] ≈ -f * res.pRES[i] / base
            end
            # The slack setpoint of the medium voltage level's low load cases.
            slack = only(
                g for g in values(data["gen"]) if
                    data["bus"]["$(g["gen_bus"])"]["bus_type"] == 3
            )
            @test slack["vg"] == 1.015
            @test data["bus"]["$(slack["gen_bus"])"]["vm_start"] == 1.015

            # High load without infeed zeroes the renewables.
            SimBench.apply_study_case!(data, grid, "hL")
            @test all(
                load_of[("sgen", id)]["pd"] == 0 for id in skipmissing(res.id)
            )
            @test load_of[("load", load.id[1])]["pd"] ≈ load.pLoad[1] / base
            @test slack["vg"] == 1.035

            @test_throws ArgumentError SimBench.apply_study_case!(data, grid, "nope")
        end
    end
end
