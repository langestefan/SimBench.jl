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
    Dataset location and the table inventory are in place. Reading grids and converting
    them to PowerModels is not implemented yet.

## Installation

```julia
using Pkg
Pkg.add(url = "https://github.com/langestefan/SimBench.jl")
```

## Dataset location

The SimBench CSV dataset is 378 MB and is not bundled with the package. Automatic download
is not implemented yet, so point the package at a local copy: the `simbench/networks`
directory of a [`simbench`](https://github.com/e2nIEE/simbench) checkout.

```julia
using SimBench
SimBench.set_data_dir!("/path/to/simbench/simbench/networks")
SimBench.scenario_path(0)
```

Equivalently, set the `SIMBENCH_DATA_DIR` environment variable to the same directory. An
explicit `set_data_dir!` takes precedence over the environment variable.

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

Individual benchmark grids are selected from this complete dataset by *SimBench code*,
for example `1-MVLV-urban-all-0-sw`.

## License

The package code is BSD-3-Clause. The SimBench **dataset** is licensed separately under
the [ODbL](https://opendatacommons.org/licenses/odbl/1.0/) by its original authors; using
it carries the ODbL's attribution and share-alike obligations. See `LICENSE`.
