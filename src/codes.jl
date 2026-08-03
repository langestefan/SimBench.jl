# SimBench codes: the identifiers that select one benchmark grid from the complete
# dataset, e.g. "1-MVLV-urban-all-0-sw".
#

"""
    SimBenchCode

A parsed SimBench code, identifying one benchmark grid.

A code is written as `version-levels-type-grid-scenario-switches`, for example
`1-MVLV-urban-all-0-sw`: version 1, an urban medium-voltage grid together with all its
low-voltage grids, scenario 0, with full switch representation.

# Fields
- `version::Int`: dataset version. Only version 1 has been published.
- `hv_level::String`: upper voltage level, one of `"EHV"`, `"HV"`, `"MV"`, `"LV"`, or
  `"complete_data"` for the whole dataset.
- `lv_level::String`: lower voltage level included in the grid, or `""` for a single
  level. `"HVMVLV"` denotes the fully interconnected grid.
- `hv_type::String`: grid character, e.g. `"mixed"`, `"urban"`, `"rural"`, `"semiurb"`,
  `"comm"`.
- `lv_grid::String`: which lower-level grid, e.g. `"all"` or `"1.108"`. Empty when
  `lv_level` is empty.
- `scenario::Int`: 0 for the present-day grid, 1 and 2 for future projections.
- `breaker_rep::Bool`: `true` keeps the full switch representation (`sw`), `false`
  requests the collapsed variant (`no_sw`).

# Examples
```jldoctest
julia> code = SimBench.SimBenchCode("1-MVLV-urban-all-0-sw");

julia> code.hv_level, code.lv_level, code.scenario
("MV", "LV", 0)

julia> string(code)
"1-MVLV-urban-all-0-sw"
```
"""
struct SimBenchCode
    version::Int
    hv_level::String
    lv_level::String
    hv_type::String
    lv_grid::String
    scenario::Int
    breaker_rep::Bool
end

"""
    SimBenchCode(code::AbstractString)

Parse a SimBench code string.

Throws `ArgumentError` if the string does not have the six dash-separated fields, or if
the version or scenario field is not an integer.
"""
function SimBenchCode(code::AbstractString)
    parts = split(code, '-')
    length(parts) == 6 || throw(
        ArgumentError(
            "SimBench code must have 6 dash-separated fields, got $(length(parts)) " *
                "in \"$code\"",
        ),
    )

    version = tryparse(Int, parts[1])
    version === nothing &&
        throw(ArgumentError("SimBench code version must be an integer, got \"$(parts[1])\""))

    scenario = tryparse(Int, parts[5])
    scenario === nothing && throw(
        ArgumentError("SimBench code scenario must be an integer, got \"$(parts[5])\""),
    )

    # The second field concatenates both voltage levels, e.g. "MVLV" or "EHVHVMVLV".
    # The upper level is the shortest prefix ending in "V"; the rest is the lower level.
    if parts[2] == "complete_data"
        hv_level, lv_level = "complete_data", ""
    else
        v = findfirst('V', parts[2])
        v === nothing && throw(
            ArgumentError(
                "SimBench code voltage level \"$(parts[2])\" contains no \"V\"",
            ),
        )
        hv_level = parts[2][1:v]
        lv_level = parts[2][(v + 1):end]
    end

    # Upstream treats any field containing "no" as no_sw.
    breaker_rep = !occursin("no", parts[6])

    return SimBenchCode(
        version, hv_level, lv_level, parts[3], parts[4], scenario, breaker_rep
    )
end

SimBenchCode(code::SimBenchCode) = code

function Base.string(code::SimBenchCode)
    return string(
        code.version, "-",
        code.hv_level, code.lv_level, "-",
        code.hv_type, "-",
        code.lv_grid, "-",
        code.scenario, "-",
        code.breaker_rep ? "sw" : "no_sw",
    )
end

Base.show(io::IO, code::SimBenchCode) = print(io, "SimBenchCode(\"", string(code), "\")")

"""
    is_complete_data(code) -> Bool

Whether `code` selects the complete dataset rather than an individual grid.
"""
is_complete_data(code::SimBenchCode) = code.hv_level == "complete_data"

"""
    complete_data_code(scenario; version=DATASET_VERSION) -> SimBenchCode

Code selecting the entire dataset for `scenario`, e.g. `1-complete_data-mixed-all-0-sw`.
"""
function complete_data_code(scenario::Integer; version::Integer = DATASET_VERSION)
    return SimBenchCode(version, "complete_data", "", "mixed", "all", scenario, true)
end

"""
    complete_grid_code(scenario; version=DATASET_VERSION) -> SimBenchCode

Code selecting the fully interconnected EHV-to-LV grid for `scenario`, e.g.
`1-EHVHVMVLV-mixed-all-0-sw`.
"""
function complete_grid_code(scenario::Integer; version::Integer = DATASET_VERSION)
    return SimBenchCode(version, "EHV", "HVMVLV", "mixed", "all", scenario, true)
end

# --- enumeration of the published code space ---------------------------------------

"""Upper voltage levels, in descending order."""
const HV_LEVELS = ("EHV", "HV", "MV", "LV")

"""Lower voltage levels that can be attached to an upper level."""
const LV_LEVELS = ("HV", "MV", "LV", "")

"""
Valid (upper, lower) voltage level pairs.

Each upper level pairs with the level directly below it, and every level except LV also
exists on its own.
"""
const VOLTAGE_LEVEL_PAIRS = (
    ("EHV", "HV"), ("EHV", ""),
    ("HV", "MV"), ("HV", ""),
    ("MV", "LV"), ("MV", ""),
    ("LV", ""),
)

"""Grid characters available at each upper voltage level."""
const HV_TYPES = Dict(
    "EHV" => ["mixed"],
    "HV" => ["mixed", "urban"],
    "MV" => ["rural", "semiurb", "urban", "comm"],
    "LV" => ["rural1", "rural2", "rural3", "semiurb4", "semiurb5", "urban6"],
)

"""Selectable lower-level grids, by upper voltage level and grid character."""
const LV_GRIDS = Dict(
    "EHV" => Dict("mixed" => ["all", "1", "2"]),
    "HV" => Dict(
        "mixed" => ["all", "1.105", "2.102", "4.101"],
        "urban" => ["all", "2.203", "3.201", "4.201"],
    ),
    "MV" => Dict(
        "rural" => ["all", "1.108", "2.107", "4.101"],
        "semiurb" => ["all", "3.202", "4.201", "5.220"],
        "urban" => ["all", "5.303", "6.305", "6.309"],
        "comm" => ["all", "3.403", "4.416", "5.401"],
    ),
)

"""
As [`LV_GRIDS`](@ref), but for the shortened dataset variant, which numbers its
lower-level grids differently.
"""
const LV_GRIDS_SHORTENED = Dict(
    "EHV" => Dict("mixed" => ["all", "1", "2"]),
    "HV" => Dict(
        "mixed" => ["all", "1.102", "2.101", "4.101"],
        "urban" => ["all", "2.202", "3.201", "4.201"],
    ),
    "MV" => Dict(
        "rural" => ["all", "1.101", "2.102", "4.101"],
        "semiurb" => ["all", "3.202", "4.201", "5.201"],
        "urban" => ["all", "5.301", "6.302", "6.302"],
        "comm" => ["all", "2.402", "4.401", "6.402"],
    ),
)

_iterable(x::AbstractString) = [x]
_iterable(x) = collect(x)

"""
    all_simbench_codes(; kwargs...) -> Vector{String}

Every SimBench code consistent with the given constraints. With no arguments, the whole
published code space.

# Keywords
- `version = DATASET_VERSION`
- `hv_level`: restrict the upper voltage level, e.g. `"MV"` or `["HV", "MV"]`.
- `lv_level`: restrict the lower voltage level. Pass `""` for single-level grids.
- `hv_type`: restrict the grid character, e.g. `"urban"`.
- `lv_grid`: override the selectable lower-level grids. Rarely needed.
- `scenario`: restrict to one or more scenarios.
- `breaker_rep`: restrict to `"sw"` or `"no_sw"`.
- `all_data = true`: include the complete-dataset and complete-grid codes.
- `shortened = false`: use the shortened dataset's grid numbering.

# Examples
```jldoctest
julia> length(SimBench.all_simbench_codes())
246

julia> SimBench.all_simbench_codes(
           hv_level = "MV", lv_level = "", hv_type = "urban", scenario = 0,
           all_data = false,
       )
2-element Vector{String}:
 "1-MV-urban--0-sw"
 "1-MV-urban--0-no_sw"
```
"""
function all_simbench_codes(;
        version::Integer = DATASET_VERSION,
        hv_level = nothing,
        lv_level = nothing,
        hv_type = nothing,
        lv_grid = nothing,
        scenario = nothing,
        breaker_rep = nothing,
        all_data::Bool = true,
        shortened::Bool = false,
    )
    hv_levels = hv_level === nothing ? collect(HV_LEVELS) : _iterable(hv_level)
    lv_levels = lv_level === nothing ? collect(LV_LEVELS) : _iterable(lv_level)
    pairs = [
        p for p in VOLTAGE_LEVEL_PAIRS if p[1] in hv_levels && p[2] in lv_levels
    ]

    types = if hv_type === nothing
        HV_TYPES
    else
        Dict(hv => _iterable(hv_type) for hv in hv_levels)
    end

    grids = if lv_grid !== nothing
        lv_grid
    elseif shortened
        LV_GRIDS_SHORTENED
    else
        LV_GRIDS
    end

    scenarios = scenario === nothing ? [0, 1, 2] : _iterable(scenario)
    breakers = breaker_rep === nothing ? ["sw", "no_sw"] : _iterable(breaker_rep)

    codes = String[]
    if all_data
        append!(codes, string(complete_data_code(s; version)) for s in scenarios)
        append!(codes, string(complete_grid_code(s; version)) for s in scenarios)
    end

    for hv in hv_levels
        for (_, lv) in Iterators.filter(p -> p[1] == hv, pairs)
            for type_ in get(types, hv, String[])
                # A single-level grid selects no lower-level grid, so the grid field is
                # left empty rather than looked up.
                lv_grids = isempty(lv) ? [""] : grids[hv][type_]
                for grid in lv_grids, scen in scenarios, breaker in breakers
                    push!(
                        codes,
                        string(
                            version, "-", hv, lv, "-", type_, "-", grid, "-",
                            scen, "-", breaker,
                        ),
                    )
                end
            end
        end
    end
    return codes
end
