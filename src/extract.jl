# Extracting one benchmark grid from the complete dataset, by SimBench code.
#
# Ported from simbench/networks/extract_simbench_grids_from_csv.py.
#
# Every element in the dataset carries a `subnet` string naming the grid it belongs to,
# such as "MV1.101" for an element inside that grid, or "MV1.101_LV1.103" for one that
# couples two grids. Extraction is a matter of deciding which subnet names are wanted
# and keeping the rows whose `subnet` matches.

"""
Grid numbers assigned to each voltage level and grid character.

The number turns a code's `hv_type` into the numeric part of a subnet name, so that
`("MV", "rural")` becomes grid 1 and hence subnet `MV1.101`.
"""
const GRID_NUMBERS = Dict(
    "EHV" => Dict("mixed" => 1),
    "HV" => Dict("mixed" => 1, "urban" => 2),
    "MV" => Dict("rural" => 1, "semiurb" => 2, "urban" => 3, "comm" => 4),
    "LV" => Dict(
        "rural1" => 1, "rural2" => 2, "rural3" => 3,
        "semiurb4" => 4, "semiurb5" => 5, "urban6" => 6,
    ),
)

"""Tables whose `subnet` may name the grid on either side of the separator."""
const TWO_SIDED_TABLES = (:Node, :Coordinates, :Measurement, :Switch, :Substation)

"""
    hv_subnet_of(hv_level, hv_type) -> (String, Int)

Subnet name and grid number of a code's upper voltage level.

MV and LV grids are numbered within their supplying grid, so they gain a `.101` suffix,
except for the two low-voltage grids supplied by the second medium-voltage grid, which
start at `.201`.
"""
function hv_subnet_of(hv_level::AbstractString, hv_type::AbstractString)
    types = get(GRID_NUMBERS, hv_level, nothing)
    types === nothing &&
        throw(ArgumentError("unknown voltage level \"$hv_level\""))
    number = get(types, hv_type, nothing)
    number === nothing && throw(
        ArgumentError(
            "unknown grid type \"$hv_type\" for $hv_level, expected one of " *
                join(sort(collect(keys(types))), ", "),
        ),
    )

    subnet = string(hv_level, number)
    hv_level in ("MV", "LV") && (subnet *= ".101")
    subnet in ("LV5.101", "LV6.101") && (subnet = subnet[1:(end - 3)] * "201")
    return subnet, number
end

hv_subnet_of(code::SimBenchCode) = hv_subnet_of(code.hv_level, code.hv_type)

"""
    lv_subnets_of(lv_level, lv_grid, hv_subnet, hv_grid_number, load) -> Vector{String}

Subnet names of the lower-level grids attached to `hv_subnet`.

Which grids exist is not recorded anywhere directly; it is recovered from the `Load`
table. Each lower-level grid appears in its supplying grid as one equivalent load whose
`subnet` starts with `"<hv_subnet>_<lv_level>"` and whose `profile` names the grid
character, e.g. `lv_rural1`. Counting those equivalent loads per character gives how
many grids of that character hang off this one, which are then numbered sequentially
from `hv_grid_number * 100 + 1`.
"""
function lv_subnets_of(
        lv_level::AbstractString, lv_grid::AbstractString, hv_subnet::AbstractString,
        hv_grid_number::Integer, load::DataFrame,
    )
    isempty(lv_level) && return String[]

    # High-voltage grids are not derived; there are exactly two.
    if lv_level == "HV"
        lv_grid == "all" && return ["HV1", "HV2"]
        lv_grid in ("1", "2") && return ["HV" * lv_grid]
        throw(
            ArgumentError(
                "lv_grid \"$lv_grid\" is not a high-voltage grid, expected all, 1 or 2",
            ),
        )
    end

    prefix = string(hv_subnet, "_", lv_level)
    counts = Dict{String, Int}()
    for (subnet, profile) in zip(load.subnet, load.profile)
        (ismissing(subnet) || ismissing(profile)) && continue
        startswith(subnet, prefix) || continue
        # The profile names the grid character, and must match the level we are after.
        uppercase(first(profile, 2)) == lv_level || continue
        counts[profile] = get(counts, profile, 0) + 1
    end

    candidates = String[]
    numbers = GRID_NUMBERS[lv_level]
    for (profile, count) in counts
        character = profile[(ncodeunits(first(profile, 2)) + 2):end]  # drop "lv_"
        number = get(numbers, character, nothing)
        number === nothing && continue
        append!(
            candidates,
            string(lv_level, number, ".", i + hv_grid_number * 100) for i in 1:count
        )
    end

    lv_grid == "all" && return candidates
    wanted = lv_level * lv_grid
    wanted in candidates || throw(
        ArgumentError(
            "lv_grid \"$lv_grid\" does not name a grid attached to $hv_subnet; " *
                "available: $(join(sort(candidates), ", "))",
        ),
    )
    return [wanted]
end

"""
    relevant_subnets(code, load) -> (Vector{String}, Vector{String})

Upper and lower subnet names selected by `code`, given the dataset's `Load` table.

For a `complete_data` code the upper list is `["complete_data"]`, which downstream reads
as "keep everything".
"""
function relevant_subnets(code::SimBenchCode, load::DataFrame)
    is_complete_data(code) && return (["complete_data"], String[])

    # The fully interconnected grid is the union of every level's selection.
    if code.lv_level == "HVMVLV"
        hv_subnets = String[]
        lv_subnets = String[]
        for (hv_level, lv_level) in (("EHV", "HV"), ("HV", "MV"), ("MV", "LV"))
            for hv_type in keys(GRID_NUMBERS[hv_level])
                subnet, number = hv_subnet_of(hv_level, hv_type)
                push!(hv_subnets, subnet)
                append!(
                    lv_subnets,
                    lv_subnets_of(lv_level, code.lv_grid, subnet, number, load),
                )
            end
        end
        return hv_subnets, lv_subnets
    end

    hv_subnet, hv_grid_number = hv_subnet_of(code)
    return [hv_subnet],
        lv_subnets_of(code.lv_level, code.lv_grid, hv_subnet, hv_grid_number, load)
end

"""
    bus_bus_switch_rows(switch, node) -> Set{Int}

Row numbers of `switch` whose endpoints are both real buses.

SimBench attaches branch-end switches to auxiliary nodes, so a switch with an auxiliary
endpoint belongs to a branch, while a switch with two ordinary endpoints couples two
buses. Only the latter are eligible to be pulled into a grid by their second subnet.
"""
function bus_bus_switch_rows(switch::DataFrame, node::DataFrame)
    node_type = Dict{String, String}()
    for (id, type) in zip(node.id, node.type)
        ismissing(id) || (node_type[id] = ismissing(type) ? "" : type)
    end

    for col in (:nodeA, :nodeB)
        unknown = [
            id for id in switch[!, col] if !ismissing(id) && !haskey(node_type, id)
        ]
        isempty(unknown) || throw(
            ArgumentError(
                "$(length(unknown)) switch endpoints in $col do not occur in the Node " *
                    "table, e.g. $(join(first(unknown, 3), ", "))",
            ),
        )
    end

    rows = Set{Int}()
    for i in 1:nrow(switch)
        a = get(node_type, switch.nodeA[i], "")
        b = get(node_type, switch.nodeB[i], "")
        aux_a = a == "auxiliary"
        aux_b = b == "auxiliary"
        aux_a && aux_b && throw(
            ArgumentError(
                "switch \"$(switch.id[i])\" has auxiliary nodes on both sides",
            ),
        )
        (aux_a || aux_b) || push!(rows, i)
    end
    return rows
end

"""Split a `subnet` value into the grid before and after the first underscore."""
function _subnet_sides(subnet)
    ismissing(subnet) && return ("", nothing)
    i = findfirst('_', subnet)
    i === nothing && return (subnet, nothing)
    j = findnext('_', subnet, i + 1)
    return (subnet[1:(i - 1)], subnet[(i + 1):(j === nothing ? lastindex(subnet) : j - 1)])
end

"""
    extract_table(df, table, hv_subnets, lv_subnets; bus_bus_switches) -> DataFrame

Keep the rows of `df` belonging to the selected subnets.

A row is kept when its subnet's first side names a selected grid, and dropped again when
it couples a selected upper grid to a selected lower one, since such an element is an
equivalent standing in for a grid that is itself included.

Tables without a `subnet` column, which is to say the profile, type and study case
tables, pass through untouched.
"""
function extract_table(
        df::DataFrame, table::Symbol, hv_subnets, lv_subnets;
        bus_bus_switches::Set{Int} = Set{Int}(),
    )
    ("complete_data" in hv_subnets || nrow(df) == 0) && return df
    hasproperty(df, :subnet) || return df

    n = nrow(df)
    sides = _subnet_sides.(df.subnet)
    upper = first.(sides)
    lower = last.(sides)
    hv = Set(hv_subnets)
    lv = Set(lv_subnets)

    # Measurements without a full element pair are bus measurements, which follow the
    # bus they sit on rather than the branch they would otherwise belong to.
    bus_measurements = if table === :Measurement
        Set(i for i in 1:n if ismissing(df.element1[i]) || ismissing(df.element2[i]))
    else
        Set{Int}()
    end

    keep = Set(i for i in 1:n if upper[i] in hv)
    if table in TWO_SIDED_TABLES
        also = Set(i for i in 1:n if lower[i] !== nothing && lower[i] in hv)
        table === :Switch && intersect!(also, bus_bus_switches)
        table === :Measurement && intersect!(also, bus_measurements)
        union!(keep, also)
    end
    union!(keep, Set(i for i in 1:n if upper[i] in lv))

    if any(!isnothing, lower)
        # Elements coupling a selected upper grid to a selected lower grid are
        # equivalents for a grid that is itself part of the selection, so they go.
        if table ∉ (:Node, :Coordinates, :Switch, :Substation)
            coupling = Set(
                i for i in 1:n if
                    upper[i] in hv && lower[i] !== nothing && lower[i] in lv
            )
            table === :Measurement && setdiff!(coupling, bus_measurements)
            setdiff!(keep, coupling)
        end

        # Upstream also drops elements pointing the other way, from a selected lower
        # grid up to a selected upper one. For the two-sided tables that branch of
        # _extract_csv_table_by_subnet compares an all-NaN frame it forgot to fill, so
        # it never selects anything; the behaviour below matches what upstream does.
        if table ∉ TWO_SIDED_TABLES
            setdiff!(
                keep,
                Set(
                    i for i in 1:n if
                        upper[i] in lv && lower[i] !== nothing && lower[i] in hv
                ),
            )
        end
    end

    return df[sort!(collect(keep)), :]
end

"""
    extract_tables(tables, code) -> Dict{Symbol, DataFrame}

Extract every table of a complete dataset down to the grid selected by `code`.
"""
function extract_tables(tables::Dict{Symbol, DataFrame}, code::SimBenchCode)
    hv_subnets, lv_subnets = relevant_subnets(code, tables[:Load])
    switches = if nrow(tables[:Switch]) > 0 && nrow(tables[:Node]) > 0
        bus_bus_switch_rows(tables[:Switch], tables[:Node])
    else
        Set{Int}()
    end

    return Dict{Symbol, DataFrame}(
        name => extract_table(
            df, name, hv_subnets, lv_subnets; bus_bus_switches = switches
        ) for (name, df) in tables
    )
end
