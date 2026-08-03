# SimBenchGrid: the intermediate representation between the CSV files and PowerModels.

"""
    SimBenchGrid

A SimBench grid as read from the CSV files: the tables in their published units, with
names rather than integer indices as identifiers.

This is the layer between parsing and the PowerModels conversion. Values are unchanged
from the dataset, so powers are in MW and MVAr, line parameters are per kilometre, and
elements reference each other by the `id` strings of the CSV files.

Every table in [`ALL_TABLES`](@ref) has an entry. Tables the dataset does not ship are
present but empty, so downstream code never has to test for their existence.

# Fields
- `code::SimBenchCode`: the grid this represents.
- `tables::Dict{Symbol, DataFrame}`: the CSV tables, keyed by table name.

# Examples
```julia
grid = SimBench.read_grid("1-complete_data-mixed-all-0-sw")
grid[:Node]              # the Node table
nrow(grid[:Line])        # 34606
```
"""
struct SimBenchGrid
    code::SimBenchCode
    tables::Dict{Symbol, DataFrame}
end

"""
    grid[table] -> DataFrame

The named table of `grid`. Throws `KeyError` for a name that is not part of the SimBench
CSV format.
"""
Base.getindex(grid::SimBenchGrid, table::Symbol) = grid.tables[table]

Base.haskey(grid::SimBenchGrid, table::Symbol) = haskey(grid.tables, table)
Base.keys(grid::SimBenchGrid) = keys(grid.tables)

"""
    scenario(grid) -> Int

Scenario the grid was read from.
"""
scenario(grid::SimBenchGrid) = grid.code.scenario

function Base.show(io::IO, ::MIME"text/plain", grid::SimBenchGrid)
    println(io, "SimBenchGrid(\"", string(grid.code), "\")")
    populated = [t for t in ALL_TABLES if nrow(grid.tables[t]) > 0]
    width = maximum(length ∘ string, populated; init = 0)
    for t in populated
        println(io, "  ", rpad(t, width), "  ", nrow(grid.tables[t]), " rows")
    end
    n_empty = length(ALL_TABLES) - length(populated)
    n_empty > 0 && print(io, "  (", n_empty, " empty tables)")
    return
end

Base.show(io::IO, grid::SimBenchGrid) =
    print(io, "SimBenchGrid(\"", string(grid.code), "\")")

const _SCENARIO_CACHE = Dict{Tuple{String, Int}, Dict{Symbol, DataFrame}}()
const _SCENARIO_CACHE_LOCK = ReentrantLock()

"""
    clear_scenario_cache!()

Empty the scenario cache filled by `read_grid(...; cache = true)`.

A cached scenario holds the complete parse, profiles included, which reaches several
hundred megabytes for scenarios 1 and 2.
"""
function clear_scenario_cache!()
    lock(_SCENARIO_CACHE_LOCK) do
        empty!(_SCENARIO_CACHE)
    end
    return nothing
end

"""
    read_grid(code; nrows=nothing, input_path=nothing, cache=false) -> SimBenchGrid

Read the grid selected by `code`, which may be a [`SimBenchCode`](@ref) or a code string.

A `complete_data` code reads a whole scenario unfiltered. Any other code reads the
scenario and then extracts the selected grid from it, so reading several grids of one
scenario costs a full parse each time unless `cache` is set.

Matching the reference implementation's `get_simbench_net`, profile columns no element
of the grid uses are dropped ([`filter_unapplied_profiles!`](@ref)) and the study cases
are reduced to the grid's own voltage level ([`filter_study_cases!`](@ref)).

# Keywords
- `nrows`: read at most this many rows of each profile table.
- `input_path`: read from this folder instead of the configured dataset location.
- `cache = false`: keep the parsed scenario in memory, so further reads with `cache`
  set extract from it instead of parsing the CSV files again. The cache holds the full
  parse, profiles included, so it costs several hundred megabytes per scenario; free it
  with [`clear_scenario_cache!`](@ref). Grids read from the cache share their type and
  profile tables, so treat the tables of a cached read as read-only.

# Examples
```julia
grid = SimBench.read_grid("1-MVLV-urban-all-0-sw")
grid = SimBench.read_grid("1-complete_data-mixed-all-0-sw")

# Read every rural low voltage grid, parsing the scenario once.
codes = SimBench.all_simbench_codes(hv_level = "LV", scenario = 0, all_data = false)
grids = [SimBench.read_grid(c; cache = true) for c in codes if endswith(c, "no_sw")]
```
"""
function read_grid(
        code::SimBenchCode; nrows::Union{Nothing, Integer} = nothing,
        input_path::Union{Nothing, AbstractString} = nothing,
        cache::Bool = false,
    )
    dir = if input_path === nothing
        scenario_path(code.scenario; version = code.version)
    else
        input_path
    end

    tables = if cache
        key = (String(dir), nrows === nothing ? -1 : Int(nrows))
        # The lock also covers the parse, so concurrent readers wait rather than
        # parsing the same scenario twice. The copy keeps downstream replacement of
        # table entries from touching the cached dict.
        copy(
            lock(_SCENARIO_CACHE_LOCK) do
                get!(() -> read_tables(dir; nrows), _SCENARIO_CACHE, key)
            end,
        )
    else
        read_tables(dir; nrows)
    end
    is_complete_data(code) || (tables = extract_tables(tables, code))
    filter_unapplied_profiles!(tables)
    filter_study_cases!(tables)
    return SimBenchGrid(code, tables)
end

read_grid(code::AbstractString; kwargs...) = read_grid(SimBenchCode(code); kwargs...)

"""
    read_grid(scenario::Integer; kwargs...) -> SimBenchGrid

Read the complete dataset for `scenario`, equivalent to passing its `complete_data` code.
"""
read_grid(scenario::Integer; kwargs...) =
    read_grid(complete_data_code(scenario); kwargs...)
