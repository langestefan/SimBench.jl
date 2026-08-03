# Time series profiles and study cases.
#
# SimBench ships a year of 15-minute profiles in relative units, and six study cases
# per voltage level. Both scale the base powers of the element tables: a profile row
# scales each element by its assigned profile column, a study case scales whole element
# groups by a single factor.

"""Profile tables and the element table each one serves."""
const PROFILE_ELEMENTS = (
    (:LoadProfile, :Load),
    (:PowerPlantProfile, :PowerPlant),
    (:RESProfile, :RES),
    (:StorageProfile, :Storage),
)

"""
    filter_unapplied_profiles!(tables) -> tables

Drop profile columns that no element of the grid uses.

The complete dataset carries every profile of every grid; after extraction most of them
scale nothing. Follows the reference implementation's `filter_unapplied_profiles`: a
profile is kept when some element's `profile` names it, with the `_pload` and `_qload`
suffix pair for loads, and the `time` column always stays.
"""
function filter_unapplied_profiles!(tables::Dict{Symbol, DataFrame})
    for (prof_tab, elm_tab) in PROFILE_ELEMENTS
        applied = unique(skipmissing(tables[elm_tab].profile))
        wanted = if elm_tab === :Load
            Set([string.(applied, "_pload"); string.(applied, "_qload")])
        else
            Set(string.(applied))
        end
        push!(wanted, string(PROFILE_TIME_COLUMN))
        df = tables[prof_tab]
        keep = [c for c in names(df) if c in wanted]
        tables[prof_tab] = df[!, keep]
    end
    return tables
end

"""
    filter_study_cases!(tables) -> tables

Keep the study case rows of the grid's lowest voltage level, dropping `voltLvl`.

SimBench defines each study case once per voltage level, differing in the load scaling
and the slack voltage setpoint, and a grid uses the rows of its lowest level. Follows
the reference implementation's `filter_loadcases`: the level is that of the smallest
nominal voltage occurring at more than two buses, so a handful of foreign-level
boundary buses do not decide it.
"""
function filter_study_cases!(tables::Dict{Symbol, DataFrame})
    sc = tables[:StudyCases]
    (nrow(sc) == 0 || nrow(tables[:Node]) == 0) && return tables

    counts = Dict{Float64, Int}()
    for vn in skipmissing(tables[:Node].vmR)
        counts[vn] = get(counts, vn, 0) + 1
    end
    candidates = [vn for (vn, c) in counts if c > 2]
    isempty(candidates) && return tables

    level = voltlvl_from_vn_kv(minimum(candidates))
    keep = [i for i in 1:nrow(sc) if _val(sc.voltLvl[i], 0) == level]
    tables[:StudyCases] = sc[keep, Not(:voltLvl)]
    return tables
end

"""
    absolute_profiles(grid) -> Dict{Tuple{Symbol, Symbol}, DataFrame}

The grid's time series in absolute units, one DataFrame per profiled element power.

Each entry multiplies the relative profile assigned to every element with that
element's base power, following the reference implementation's `get_absolute_values`.
The keys name the element table and the scaled column:

| key | unit | scaled by |
| --- | --- | --- |
| `(:Load, :pLoad)` | MW | `LoadProfile.<profile>_pload` |
| `(:Load, :qLoad)` | MVAr | `LoadProfile.<profile>_qload` |
| `(:RES, :pRES)` | MW | `RESProfile.<profile>` |
| `(:PowerPlant, :pPP)` | MW | `PowerPlantProfile.<profile>` |
| `(:Storage, :pStor)` | MW | `StorageProfile.<profile>` |

Each DataFrame has the profile `time` column first and one column per element id. An
element without an assigned profile keeps its base power at every step. Reactive power
of generation is not profiled; SimBench only ships scaling for the powers above.

The result covers as many rows as the grid's profile tables hold, so a grid read with
`nrows` gives a correspondingly short result.

# Examples
```julia
grid = SimBench.read_grid("1-MV-rural--0-no_sw")
profiles = SimBench.absolute_profiles(grid)
profiles[(:Load, :pLoad)]     # 35136 rows, one column per load, in MW
```
"""
function absolute_profiles(grid::SimBenchGrid)
    return Dict{Tuple{Symbol, Symbol}, DataFrame}(
        (:Load, :pLoad) =>
            _absolute_profile(grid[:Load], grid[:LoadProfile], :pLoad, "_pload"),
        (:Load, :qLoad) =>
            _absolute_profile(grid[:Load], grid[:LoadProfile], :qLoad, "_qload"),
        (:RES, :pRES) => _absolute_profile(grid[:RES], grid[:RESProfile], :pRES, ""),
        (:PowerPlant, :pPP) =>
            _absolute_profile(grid[:PowerPlant], grid[:PowerPlantProfile], :pPP, ""),
        (:Storage, :pStor) =>
            _absolute_profile(grid[:Storage], grid[:StorageProfile], :pStor, ""),
    )
end

function _absolute_profile(
        elements::DataFrame, profile::DataFrame, column::Symbol, suffix::AbstractString,
    )
    n = nrow(profile)
    out = DataFrame(PROFILE_TIME_COLUMN => profile[!, PROFILE_TIME_COLUMN])
    for i in 1:nrow(elements)
        id = elements.id[i]
        ismissing(id) && continue
        base = _val(elements[i, column], 0.0)
        name = elements.profile[i]
        out[!, id] = if ismissing(name)
            # No profile assigned scales by one, as upstream assumes.
            fill(Float64(base), n)
        else
            col = string(name, suffix)
            hasproperty(profile, col) || throw(
                ArgumentError(
                    "profile \"$col\" assigned to \"$id\" is missing from the " *
                        "profile table",
                ),
            )
            profile[!, col] .* base
        end
    end
    return out
end

"""
    apply_profile!(data, profiles, t) -> data

Set the powers of PowerModels data `data` to time step `t` of `profiles`.

`profiles` is the result of [`absolute_profiles`](@ref) for the same grid, and `t` is
either a row number or a `DateTime` matching the profile `time` column. Elements are
matched through their `source_id`, so the data may be reindexed or filtered. Powers are
converted to per unit on the data's `baseMVA`.

Values are taken from the profiles, not scaled from the current state, so repeated
application is safe. Affected are load `pd`/`qd`, including the negative loads standing
in for renewables under `pq_as = :load`, generator `pg`, with the `pmin == pmax` pin of
a non-dispatchable generator moved along, and storage `ps`.

!!! warning "Daylight saving time"
    Profile timestamps are local time, so across the DST transitions they are not
    unique; a `DateTime` in the repeated autumn hour finds the first occurrence. Row
    numbers are unambiguous.

# Examples
```julia
grid = SimBench.read_grid("1-MV-rural--0-no_sw")
data = SimBench.powermodels_data(grid)
profiles = SimBench.absolute_profiles(grid)
SimBench.apply_profile!(data, profiles, 5000)
result = PowerModels.compute_ac_pf(data)
```
"""
function apply_profile!(data::AbstractDict, profiles::AbstractDict, t)
    step = _profile_step(profiles, t)
    base = data["baseMVA"]
    lookup(key) = get(profiles, key, nothing)
    lp, lq = lookup((:Load, :pLoad)), lookup((:Load, :qLoad))
    rp = lookup((:RES, :pRES))
    pp = lookup((:PowerPlant, :pPP))
    sp = lookup((:Storage, :pStor))
    at(df, id) = df[step, id] / base

    for load in values(data["load"])
        kind, id = load["source_id"]
        if kind == "load"
            lp === nothing || (load["pd"] = at(lp, id))
            lq === nothing || (load["qd"] = at(lq, id))
        elseif kind == "sgen" && rp !== nothing
            load["pd"] = -at(rp, id)
        end
    end

    for gen in values(data["gen"])
        kind, id = gen["source_id"]
        df = kind == "gen" ? pp : kind == "sgen" ? rp : nothing
        df === nothing && continue
        pinned = gen["pmin"] == gen["pmax"]
        gen["pg"] = at(df, id)
        pinned && (gen["pmin"] = gen["pmax"] = gen["pg"])
    end

    if sp !== nothing
        for strg in values(data["storage"])
            kind, id = strg["source_id"]
            kind == "storage" && (strg["ps"] = at(sp, id))
        end
    end
    return data
end

_profile_step(profiles::AbstractDict, t::Integer) = Int(t)

function _profile_step(profiles::AbstractDict, t::DateTime)
    for df in values(profiles)
        nrow(df) > 0 || continue
        i = findfirst(==(t), df[!, PROFILE_TIME_COLUMN])
        i === nothing || return i
    end
    throw(ArgumentError("no profile row at $t"))
end

"""
    apply_study_case!(data, grid, case) -> data

Scale the powers of PowerModels data `data` to one of the grid's study cases.

SimBench defines six study cases: `hL` and `n1` at full load without renewable
infeed, `hW` and `hPV` at full load with high wind or high solar infeed, and `lW` and
`lPV` at low load with the same infeed. Following the reference implementation's
`get_absolute_values`, a case scales:

- every load's `pd` and `qd` by the `pload` and `qload` factors,
- every renewable's power by type: `Wind_p` where the type contains `Wind` or `WP`,
  `PV_p` where it contains `PV`, and `RES_p` otherwise. The match is case sensitive,
  as upstream; the extra-high-voltage grid types its renewables in lower case, so they
  all fall to `RES_p` there,
- the voltage setpoint of every reference bus, and of the generators on one, to
  `Slack_vm`.

Factors apply to the base powers of the grid tables, not to the current state of
`data`, so repeated application is safe. The base case itself, called `bc` upstream, is
the unmodified conversion. Dispatchable power plants and storage are not part of the
study case definition and keep their base powers.

# Examples
```julia
grid = SimBench.read_grid("1-MV-rural--0-no_sw"; nrows = 1)
data = SimBench.powermodels_data(grid)
SimBench.apply_study_case!(data, grid, "hW")
```
"""
function apply_study_case!(data::AbstractDict, grid::SimBenchGrid, case::AbstractString)
    sc = grid[:StudyCases]
    # A grid read without filtering still carries every voltage level's rows.
    hasproperty(sc, :voltLvl) &&
        (sc = filter_study_cases!(Dict(:StudyCases => sc, :Node => grid[:Node]))[:StudyCases])

    cases = coalesce.(sc[!, Symbol("Study Case")], "")
    i = findfirst(==(case), cases)
    i === nothing && throw(
        ArgumentError(
            "unknown study case \"$case\"; available: $(join(unique(cases), ", "))",
        ),
    )
    row = sc[i, :]
    factors = (
        pload = _val(row.pload, 1.0), qload = _val(row.qload, 1.0),
        Wind_p = _val(row.Wind_p, 1.0), PV_p = _val(row.PV_p, 1.0),
        RES_p = _val(row.RES_p, 1.0), Slack_vm = row.Slack_vm,
    )
    base = data["baseMVA"]

    load = grid[:Load]
    load_pq = Dict{String, Tuple{Float64, Float64}}(
        id => (_val(load.pLoad[i], 0.0), _val(load.qLoad[i], 0.0)) for
            (i, id) in enumerate(load.id) if !ismissing(id)
    )
    res = grid[:RES]
    res_p = Dict{String, Float64}()
    for i in 1:nrow(res)
        id = res.id[i]
        ismissing(id) && continue
        type = _val(res.type[i], "")
        factor = if occursin("PV", type)
            factors.PV_p
        elseif occursin("Wind", type) || occursin("WP", type)
            factors.Wind_p
        else
            factors.RES_p
        end
        res_p[id] = _val(res.pRES[i], 0.0) * factor
    end

    for l in values(data["load"])
        kind, id = l["source_id"]
        if kind == "load" && haskey(load_pq, id)
            p, q = load_pq[id]
            l["pd"] = p * factors.pload / base
            l["qd"] = q * factors.qload / base
        elseif kind == "sgen" && haskey(res_p, id)
            l["pd"] = -res_p[id] / base
        end
    end

    for gen in values(data["gen"])
        kind, id = gen["source_id"]
        if kind == "sgen" && haskey(res_p, id)
            pinned = gen["pmin"] == gen["pmax"]
            gen["pg"] = res_p[id] / base
            pinned && (gen["pmin"] = gen["pmax"] = gen["pg"])
        end
        bus = data["bus"][string(gen["gen_bus"])]
        if bus["bus_type"] == BUS_REF && !ismissing(factors.Slack_vm)
            gen["vg"] = factors.Slack_vm
            bus["vm"] = factors.Slack_vm
            haskey(bus, "vm_start") && (bus["vm_start"] = factors.Slack_vm)
        end
    end
    return data
end
