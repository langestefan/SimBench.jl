# Locating the SimBench CSV dataset on disk.
#
# By default the dataset comes from a lazy Pkg artifact pointing at the upstream project's
# PyPI release, downloaded on first use. An explicit `set_data_dir!` call or the
# SIMBENCH_DATA_DIR environment variable overrides that with a local copy.

"""
    SimBenchDataError <: Exception

Raised when the SimBench CSV dataset cannot be located or is incomplete.
"""
struct SimBenchDataError <: Exception
    msg::String
end

Base.showerror(io::IO, e::SimBenchDataError) =
    print(io, "SimBenchDataError: ", e.msg)

"""Environment variable pointing at the directory holding the scenario folders."""
const DATA_DIR_ENV = "SIMBENCH_DATA_DIR"

"""Scenario identifiers of the published SimBench dataset."""
const SCENARIOS = (0, 1, 2)

"""Dataset version. Only version 1 has been published."""
const DATASET_VERSION = 1

"""
Release of the upstream `simbench` project the dataset artifact is taken from.

The artifact is that project's own PyPI source distribution, which ships every CSV, so
the data is the published one rather than a copy maintained here.
"""
const DATASET_RELEASE = v"1.6.2"

"""Path of the scenario folders within the unpacked artifact."""
const ARTIFACT_SUBPATH =
    joinpath("simbench-$(DATASET_RELEASE)", "simbench", "networks")

const _DATA_DIR = Ref{Union{Nothing, String}}(nothing)

"""
    artifact_data_dir() -> String

Dataset directory inside the lazy artifact, downloading it on first call.

The download is roughly 88 MB and unpacks to about 399 MB, covering all three scenarios.
"""
function artifact_data_dir()
    return joinpath(artifact"simbench_dataset", ARTIFACT_SUBPATH)
end

"""
    complete_data_folder(scenario; version=DATASET_VERSION) -> String

Folder name holding the complete grid data for `scenario`, e.g.
`"1-complete_data-mixed-all-0-sw"`.
"""
function complete_data_folder(scenario::Integer; version::Integer = DATASET_VERSION)
    return string(version, "-complete_data-mixed-all-", scenario, "-sw")
end

"""
    set_data_dir!(dir) -> String

Point SimBench.jl at a directory containing the scenario folders (the `networks`
directory of a `simbench` Python checkout, for example). Overrides `SIMBENCH_DATA_DIR`
for the current session.
"""
function set_data_dir!(dir::AbstractString)
    path = abspath(expanduser(dir))
    isdir(path) || throw(SimBenchDataError("not a directory: $path"))
    _DATA_DIR[] = path
    return path
end

"""
    reset_data_dir!()

Forget a directory set with [`set_data_dir!`](@ref) and fall back to `SIMBENCH_DATA_DIR`.
"""
reset_data_dir!() = (_DATA_DIR[] = nothing)

"""
    data_dir() -> String

Directory containing the SimBench scenario folders.

Resolution order: an explicit [`set_data_dir!`](@ref), then the `SIMBENCH_DATA_DIR`
environment variable, then the lazy artifact. Falling through to the artifact downloads
about 88 MB on first use.
"""
function data_dir()::String
    configured = _DATA_DIR[]
    configured === nothing || return configured

    dir = get(ENV, DATA_DIR_ENV, nothing)
    if dir !== nothing
        path = abspath(expanduser(dir))
        isdir(path) || throw(
            SimBenchDataError("$DATA_DIR_ENV points at a non-existent directory: $path"),
        )
        return path
    end

    try
        return artifact_data_dir()
    catch err
        throw(
            SimBenchDataError(
                """
                The SimBench dataset could not be obtained: $(sprint(showerror, err))

                It is normally downloaded on first use, about 88 MB, from the upstream
                project's PyPI release. If this machine has no network access, point the
                package at a local copy instead:

                    SimBench.set_data_dir!("/path/to/simbench/simbench/networks")

                or set the $DATA_DIR_ENV environment variable to the same directory. It
                must contain the scenario folders \
                $(join(complete_data_folder.(SCENARIOS), ", ")).""",
            ),
        )
    end
end

"""
    scenario_path(scenario; version=DATASET_VERSION) -> String

Absolute path to the dataset folder for `scenario`, validated to exist and to hold every
table in [`REQUIRED_TABLES`](@ref).
"""
function scenario_path(scenario::Integer; version::Integer = DATASET_VERSION)
    scenario in SCENARIOS || throw(
        ArgumentError(
            "scenario must be one of $(join(SCENARIOS, ", ")), got $scenario",
        ),
    )

    path = joinpath(data_dir(), complete_data_folder(scenario; version))
    isdir(path) || throw(
        SimBenchDataError(
            "scenario $scenario folder not found: $path\n" *
                "Contents of $(data_dir()): $(join(readdir(data_dir()), ", "))",
        ),
    )

    absent = missing_tables(path)
    isempty(absent) || throw(
        SimBenchDataError(
            "scenario $scenario at $path is missing required tables: " *
                join(absent, ", "),
        ),
    )

    return path
end

"""
    available_tables(dir) -> Vector{Symbol}

Tables of the SimBench CSV format that are present as files in `dir`, in schema order.
"""
function available_tables(dir::AbstractString)
    return [t for t in ALL_TABLES if isfile(joinpath(dir, csv_filename(t)))]
end

"""
    missing_tables(dir) -> Vector{Symbol}

Required tables absent from `dir`. Empty for a complete dataset folder. Tables in
[`OPTIONAL_TABLES`](@ref) are never reported.
"""
function missing_tables(dir::AbstractString)
    return [t for t in REQUIRED_TABLES if !isfile(joinpath(dir, csv_filename(t)))]
end

"""
    table_path(dir, table) -> String

Path to `table`'s CSV file inside dataset folder `dir`. Does not check existence:
optional tables are legitimately absent.
"""
table_path(dir::AbstractString, table::Symbol) = joinpath(dir, csv_filename(table))
