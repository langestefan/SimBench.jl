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

# --- column names and types --------------------------------------------------------
#
# Ported from format_information.py (all_columns, all_dtypes), with one correction: the
# reference implementation's StudyCases entry names the first column "Study Cases" and
# omits "voltLvl" entirely. The published files use "Study Case" and do carry "voltLvl",
# so the header below follows the data.
#
# Profile tables are deliberately absent. Their column sets are per-dataset (scenario 2
# ships 193 LoadProfile and 321 PowerPlantProfile columns, against the 55 and 1 that
# upstream nominally lists), so they are inferred at read time instead.

const _STR = String
const _INT = Int
const _FLT = Float64

const TABLE_COLUMNS = Dict{Symbol, Vector{Symbol}}(
    :Coordinates => [:id, :x, :y, :subnet, :voltLvl],
    :ExternalNet => [
        :id, :node, :calc_type, :dspf, :pExtNet, :qExtNet, :pWardShunt, :qWardShunt,
        :rXWard, :xXWard, :vmXWard, :subnet, :voltLvl,
    ],
    :Line => [:id, :nodeA, :nodeB, :type, :length, :loadingMax, :subnet, :voltLvl],
    :LineType => [:id, :r, :x, :b, :iMax, :type],
    :Load => [:id, :node, :profile, :pLoad, :qLoad, :sR, :subnet, :voltLvl],
    :Shunt => [:id, :node, :p0, :q0, :vmR, :step, :subnet, :voltLvl],
    :Node => [
        :id, :type, :vmSetp, :vaSetp, :vmR, :vmMin, :vmMax, :substation, :coordID,
        :subnet, :voltLvl,
    ],
    :Measurement => [:id, :element1, :element2, :variable, :subnet, :voltLvl],
    :PowerPlant => [
        :id, :node, :type, :profile, :calc_type, :dspf, :pPP, :qPP, :sR, :pMin, :pMax,
        :qMin, :qMax, :subnet, :voltLvl,
    ],
    :RES => [
        :id, :node, :type, :profile, :calc_type, :pRES, :qRES, :sR, :subnet, :voltLvl,
    ],
    :Storage => [
        :id, :node, :type, :profile, :pStor, :qStor, :chargeLevel, :sR, :eStore,
        :etaStore, :sdStore, :pMin, :pMax, :qMin, :qMax, :subnet, :voltLvl,
    ],
    :Substation => [:id, :subnet, :voltLvl],
    :Switch => [:id, :nodeA, :nodeB, :type, :cond, :substation, :subnet, :voltLvl],
    :Transformer => [
        :id, :nodeHV, :nodeLV, :type, :tappos, :autoTap, :autoTapSide, :loadingMax,
        :substation, :subnet, :voltLvl,
    ],
    :TransformerType => [
        :id, :sR, :vmHV, :vmLV, :va0, :vmImp, :pCu, :pFe, :iNoLoad, :tapable, :tapside,
        :dVm, :dVa, :tapNeutr, :tapMin, :tapMax,
    ],
    :Transformer3W => [
        :id, :nodeHV, :nodeMV, :nodeLV, :type, :tapposHV, :tapposMV, :tapposLV,
        :autoTap, :autoTapSide, :loadingMax, :substation, :subnet, :voltLvl,
    ],
    :Transformer3WType => [
        :id, :sRHV, :sRMV, :sRLV, :vmHV, :vmMV, :vmLV, :vaHVMV, :vaHVLV, :vmImpHVMV,
        :vmImpHVLV, :vmImpMVLV, :pCuHV, :pCuMV, :pCuLV, :pFe, :iNoLoad, :tapable,
        :tapside, :dVmHV, :dVmMV, :dVmLV, :dVaHV, :dVaMV, :dVaLV, :tapNeutrHV,
        :tapNeutrMV, :tapNeutrLV, :tapMinHV, :tapMinMV, :tapMinLV, :tapMaxHV,
        :tapMaxMV, :tapMaxLV,
    ],
    :DCLineType => [
        :id, :pDCLine, :relPLosses, :fixPLosses, :pMax, :qMinA, :qMinB, :qMaxA, :qMaxB,
    ],
    :StudyCases => [
        Symbol("Study Case"), :voltLvl, :pload, :qload, :Wind_p, :PV_p, :RES_p,
        :Slack_vm,
    ],
    :NodePFResult => [:node, :vm, :va, :substation, :subnet, :voltLvl],
)

const TABLE_COLTYPES = Dict{Symbol, Vector{DataType}}(
    :Coordinates => [_STR, _FLT, _FLT, _STR, _INT],
    :ExternalNet => [fill(_STR, 3); fill(_FLT, 8); _STR; _INT],
    :Line => [fill(_STR, 4); _FLT; _FLT; _STR; _INT],
    :LineType => [_STR; fill(_FLT, 4); _STR],
    :Load => [fill(_STR, 3); fill(_FLT, 3); _STR; _INT],
    :Shunt => [_STR, _STR, _FLT, _FLT, _FLT, _INT, _STR, _INT],
    :Node => [fill(_STR, 2); fill(_FLT, 5); fill(_STR, 3); _INT],
    :Measurement => [fill(_STR, 5); _INT],
    :PowerPlant => [fill(_STR, 5); fill(_FLT, 8); _STR; _INT],
    :RES => [fill(_STR, 5); fill(_FLT, 3); _STR; _INT],
    :Storage => [fill(_STR, 4); fill(_FLT, 11); _STR; _INT],
    :Substation => [_STR, _STR, _INT],
    :Switch => [fill(_STR, 4); _INT; fill(_STR, 2); _INT],
    :Transformer => [
        fill(_STR, 4); _INT; _INT; _STR; _FLT; _STR; _STR; _INT
    ],
    :TransformerType => [
        _STR; fill(_FLT, 8); _INT; _STR; _FLT; _FLT; _INT; _INT; _INT
    ],
    :Transformer3W => [
        fill(_STR, 5); fill(_FLT, 3); _INT; _STR; _FLT; _STR; _STR; _INT
    ],
    :Transformer3WType => [
        _STR; fill(_FLT, 16); _INT; _STR; fill(_FLT, 6); fill(_INT, 9)
    ],
    :DCLineType => [_STR; fill(_FLT, 8)],
    :StudyCases => [_STR; _INT; fill(_FLT, 6)],
    :NodePFResult => [_STR, _FLT, _FLT, _STR, _STR, _INT],
)

"""
    has_fixed_schema(table::Symbol) -> Bool

Whether `table` has a known, fixed set of columns.

False for the profile tables, whose columns name the profiles present in a particular
dataset and are therefore inferred when reading.
"""
has_fixed_schema(table::Symbol) = haskey(TABLE_COLUMNS, table)

"""
    table_columns(table::Symbol) -> Vector{Symbol}

Expected column names of `table`, in file order. Throws for profile tables, which have
no fixed schema; see [`has_fixed_schema`](@ref).
"""
function table_columns(table::Symbol)
    cols = get(TABLE_COLUMNS, table, nothing)
    cols === nothing && throw(
        ArgumentError(
            table in PROFILE_TABLES ?
                "$table is a profile table; its columns are dataset-specific and are " *
                "inferred when reading" :
                "unknown table :$table",
        ),
    )
    return cols
end

"""
    table_coltypes(table::Symbol) -> Vector{DataType}

Element type of each column of `table`, in file order, ignoring missing values. Throws
for profile tables; see [`has_fixed_schema`](@ref).
"""
function table_coltypes(table::Symbol)
    table_columns(table)  # for the error message
    return TABLE_COLTYPES[table]
end
