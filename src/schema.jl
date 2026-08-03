# SimBench CSV format: table inventory.
#
# Ported from simbench/converter/format_information.py (csv_tablenames).
# Column names and column types are added later.

"""Element tables: one row per grid component."""
const ELEMENT_TABLES = (
    :ExternalNet,
    :Line,
    :Load,
    :Shunt,
    :Node,
    :Measurement,
    :PowerPlant,
    :RES,
    :Storage,
    :Substation,
    :Switch,
    :Transformer,
    :Transformer3W,
    :Coordinates,
)

"""Profile tables: one row per time step, one column per named profile."""
const PROFILE_TABLES =
    (:LoadProfile, :PowerPlantProfile, :RESProfile, :StorageProfile)

"""Type (library) tables: reusable electrical parameter sets referenced by element tables."""
const TYPE_TABLES =
    (:LineType, :DCLineType, :TransformerType, :Transformer3WType)

"""Study-case table: scaling factors per load case and voltage level."""
const CASE_TABLES = (:StudyCases,)

"""Precomputed power-flow result tables shipped alongside some datasets."""
const RESULT_TABLES = (:NodePFResult,)

const TABLE_GROUPS = (
    elements = ELEMENT_TABLES,
    profiles = PROFILE_TABLES,
    types = TYPE_TABLES,
    cases = CASE_TABLES,
    res_elements = RESULT_TABLES,
)

"""
    csv_tablenames(group::Symbol) -> Vector{Symbol}
    csv_tablenames(groups) -> Vector{Symbol}

Table names belonging to one or more groups. Valid groups are `:elements`, `:profiles`,
`:types`, `:cases` and `:res_elements`. Order follows the group order given, and duplicates
are preserved in group order (matching upstream `csv_tablenames`).

# Examples
```jldoctest
julia> SimBench.csv_tablenames(:types)
4-element Vector{Symbol}:
 :LineType
 :DCLineType
 :TransformerType
 :Transformer3WType
```
"""
function csv_tablenames(group::Symbol)
    haskey(TABLE_GROUPS, group) || throw(
        ArgumentError(
            "unknown table group :$group, expected one of $(join(keys(TABLE_GROUPS), ", "))",
        ),
    )
    return collect(TABLE_GROUPS[group])
end

function csv_tablenames(groups)
    names = Symbol[]
    for group in groups
        append!(names, csv_tablenames(group))
    end
    return names
end

"""
All table names in the SimBench CSV format, across every group.
"""
const ALL_TABLES = Tuple(
    csv_tablenames((:elements, :profiles, :types, :cases, :res_elements))
)

"""
Tables present in every published v1 scenario folder.

Upstream treats a missing `Node` or `Load` table as an error and silently substitutes an
empty table for anything else. We validate all tables common to the three scenarios, so
that a truncated download fails loudly and early rather than producing a grid with
silently missing components.
"""
const REQUIRED_TABLES = (
    :Node,
    :Load,
    :Line,
    :LineType,
    :Transformer,
    :TransformerType,
    :Switch,
    :ExternalNet,
    :RES,
    :PowerPlant,
    :Substation,
    :Coordinates,
    :Measurement,
    :StudyCases,
    :LoadProfile,
    :RESProfile,
    :PowerPlantProfile,
)

"""
Tables shipped only by the future scenarios (1 and 2), not by the base scenario 0.

Scenario 0 is the present-day grid; scenarios 1 and 2 project storage and HVDC build-out
onto it. Scenario 2 carries 6,533 `Storage` units, more than it has `RES` units, so
these are load-bearing tables, not schema padding.
"""
const SCENARIO_TABLES = (:Storage, :StorageProfile, :DCLineType)

"""
Tables defined by the CSV format but shipped by no v1 scenario.

`Shunt`, three-winding transformers and precomputed node results are part of the format;
no published SimBench grid uses them. They are read as empty tables when absent.
"""
const UNUSED_TABLES =
    (:Shunt, :Transformer3W, :Transformer3WType, :NodePFResult)

"""
Tables that need not be present in a dataset folder: [`SCENARIO_TABLES`](@ref) and
[`UNUSED_TABLES`](@ref) together.
"""
const OPTIONAL_TABLES = Tuple(setdiff(ALL_TABLES, REQUIRED_TABLES))

"""
    csv_filename(table::Symbol) -> String

File name of `table` within a SimBench dataset folder.
"""
csv_filename(table::Symbol) = string(table, ".csv")
