# Reading SimBench CSV files into DataFrames.

"""Column separator used by the SimBench CSV files."""
const CSV_DELIM = ';'

"""Sentinel written for missing values."""
const CSV_MISSING = "NULL"

"""
Timestamp format of the `time` column of the profile tables.

!!! warning "Local time, not a uniform series"
    Profile timestamps are local German wall-clock time (CET/CEST), so they are neither
    strictly increasing nor evenly spaced across daylight-saving transitions. In the
    published 2016 profiles the spring transition jumps from `2016-03-27T01:45` to
    `03:00`, and the autumn transition repeats `02:00` through `02:45` on
    `2016-10-30`, giving four duplicated timestamps and one backward step.

    The row index, not the timestamp, is the uniform quarter-hour sequence: every
    profile table has exactly 35136 rows, being 366 days of 2016 at 96 steps per day.
"""
const PROFILE_TIME_FORMAT = dateformat"dd.mm.yyyy HH:MM"

"""Name of the timestamp column of the profile tables."""
const PROFILE_TIME_COLUMN = :time

"""
    empty_table(table::Symbol) -> DataFrame

An empty DataFrame with `table`'s columns and types.

Used in place of tables that a dataset does not ship, so that downstream code can treat
an absent table as an empty one. Profile tables get a lone `time` column, since their
remaining columns are dataset-specific.
"""
function empty_table(table::Symbol)
    if !has_fixed_schema(table)
        return DataFrame(PROFILE_TIME_COLUMN => DateTime[])
    end
    cols = table_columns(table)
    types = table_coltypes(table)
    return DataFrame([c => Union{Missing, T}[] for (c, T) in zip(cols, types)])
end

"""
    read_table(dir, table; nrows=nothing, strict=true) -> DataFrame

Read one SimBench CSV table from dataset folder `dir`.

Values of `"NULL"` become `missing`. Every column of a fixed-schema table is typed
`Union{Missing, T}` regardless of whether that particular file uses `"NULL"`, so the
element types do not vary with the data. Profile tables get a `DateTime` `time` column
and `Float64` profile columns.

If the file is absent, returns [`empty_table`](@ref). This matches the reference
implementation, which substitutes an empty table for anything it cannot read, and is
what makes the scenario-dependent `Storage`, `StorageProfile` and `DCLineType` tables
safe to request from any scenario.

# Keywords
- `nrows`: read at most this many data rows. Applies to profile tables only, matching
  upstream, where it exists to avoid loading a full year of 15-minute data.
- `strict`: if true, throw when the file's header does not match the expected schema.
"""
function read_table(
        dir::AbstractString, table::Symbol; nrows::Union{Nothing, Integer} = nothing,
        strict::Bool = true,
    )
    path = table_path(dir, table)
    isfile(path) || return empty_table(table)

    return if has_fixed_schema(table)
        _read_fixed_table(path, table, strict)
    else
        _read_profile_table(path, nrows)
    end
end

function _read_fixed_table(path::AbstractString, table::Symbol, strict::Bool)
    cols = table_columns(table)
    types = table_coltypes(table)
    df = CSV.read(
        path, DataFrame;
        delim = CSV_DELIM,
        missingstring = CSV_MISSING,
        types = Dict(c => Union{Missing, T} for (c, T) in zip(cols, types)),
        stringtype = String,
        # Report a header mismatch ourselves, with the full diff, rather than letting
        # CSV.jl reject the schema column-by-column.
        validate = false,
    )

    if strict && propertynames(df) != cols
        extra = setdiff(propertynames(df), cols)
        absent = setdiff(cols, propertynames(df))
        throw(
            ArgumentError(
                "$(basename(path)) header does not match the $table schema" *
                    (isempty(absent) ? "" : "; missing columns: $(join(absent, ", "))") *
                    (isempty(extra) ? "" : "; unexpected columns: $(join(extra, ", "))") *
                    (
                    isempty(absent) && isempty(extra) ?
                        "; same columns in a different order" : ""
                ),
            ),
        )
    end
    return df
end

function _read_profile_table(path::AbstractString, nrows::Union{Nothing, Integer})
    # The time column is a timestamp; every other column is a profile of Float64.
    coltype(_, name) = name === PROFILE_TIME_COLUMN ? String : Float64
    df = CSV.read(
        path, DataFrame;
        delim = CSV_DELIM,
        missingstring = CSV_MISSING,
        types = coltype,
        stringtype = String,
        limit = nrows === nothing ? typemax(Int) : nrows,
    )

    if hasproperty(df, PROFILE_TIME_COLUMN)
        df[!, PROFILE_TIME_COLUMN] =
            DateTime.(df[!, PROFILE_TIME_COLUMN], PROFILE_TIME_FORMAT)
    end
    return df
end

"""
    read_tables(dir, tables=ALL_TABLES; nrows=nothing, strict=true) -> Dict{Symbol,DataFrame}

Read several SimBench CSV tables from dataset folder `dir`.

Tables whose files are absent come back empty, so the result always has an entry for
every requested table.
"""
function read_tables(
        dir::AbstractString, tables = ALL_TABLES;
        nrows::Union{Nothing, Integer} = nothing, strict::Bool = true,
    )
    return Dict{Symbol, DataFrame}(
        t => read_table(dir, t; nrows, strict) for t in tables
    )
end
