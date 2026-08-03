```@meta
CurrentModule = SimBench
```

# SimBench.jl

Read the [SimBench](https://simbench.net) benchmark grid dataset and convert it to
[PowerModels.jl](https://github.com/lanl-ansi/PowerModels.jl) network data.

SimBench is a set of German EHV/HV/MV/LV benchmark grids with matched load and generation
time series, developed by University of Kassel, TU Dortmund, RWTH Aachen and Fraunhofer
IEE. This package is a Julia port of the [reference
implementation](https://github.com/e2nIEE/simbench), which targets pandapower.

!!! warning "Work in progress"
    Reading any published benchmark grid into a [`SimBench.SimBenchGrid`](@ref) and
    converting it to PowerModels network data works. Applying load and generation
    profiles and study cases is not implemented yet.

## Installation

```julia
using Pkg
Pkg.add(url = "https://github.com/langestefan/SimBench.jl")
```

## Dataset location

The dataset downloads itself on first use, as a lazy `Pkg` artifact, so installing the
package fetches nothing until you ask for a grid. The download is 88 MB and unpacks to
about 399 MB, covering all three scenarios.

```julia
using SimBench
SimBench.scenario_path(0)     # downloads on the first call
```

The artifact points at the upstream project's own
[PyPI release](https://pypi.org/project/simbench/) rather than a copy hosted here, so the
data is the published one and this package is not a redistributor of it. PyPI filenames
are immutable once uploaded, which keeps the recorded checksum valid.

To use a local copy instead, point the package at a directory holding the scenario
folders:

```julia
SimBench.set_data_dir!("/path/to/simbench/simbench/networks")
```

`SIMBENCH_DATA_DIR` is the environment-variable equivalent. Resolution order is
[`SimBench.set_data_dir!`](@ref), then `SIMBENCH_DATA_DIR`, then
[`SimBench.artifact_data_dir`](@ref).

## Dataset structure

Three scenario folders, one per projection year, holding the complete grid data:

| Scenario | Folder | Size |
| --- | --- | --- |
| 0 | `1-complete_data-mixed-all-0-sw` | 111 MB |
| 1 | `1-complete_data-mixed-all-1-sw` | 133 MB |
| 2 | `1-complete_data-mixed-all-2-sw` | 134 MB |

Scenario 0 is the present-day grid. Scenarios 1 and 2 project storage and HVDC build-out
onto it, and are the only ones shipping the `Storage`, `StorageProfile` and `DCLineType`
tables ([`SimBench.SCENARIO_TABLES`](@ref)).

## Reading a grid

```julia
julia> grid = SimBench.read_grid(0)
SimBenchGrid("1-complete_data-mixed-all-0-sw")
  Coordinates        37693 rows
  ExternalNet          444 rows
  Line               34606 rows
  ...

julia> grid[:Line]
34606x8 DataFrame
```

Tables come back as `DataFrame`s in the units the dataset publishes, with the CSV `id`
strings as identifiers. Tables a scenario does not ship are present but empty, so code
never has to test for them.

Individual benchmark grids are selected from this complete dataset by *SimBench code*,
for example `1-MVLV-urban-all-0-sw`. Selecting one is not implemented yet.

## License

The package code is BSD-3-Clause. The SimBench **dataset** is licensed separately under
the [ODbL](https://opendatacommons.org/licenses/odbl/1.0/) by its original authors; using
it carries the ODbL's attribution and share-alike obligations. See `LICENSE`.
