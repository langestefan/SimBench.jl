# SimBench.jl

[![CI](https://github.com/langestefan/SimBench.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/langestefan/SimBench.jl/actions/workflows/CI.yml)
[![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://langestefan.github.io/SimBench.jl/dev/)
[![License: BSD-3](https://img.shields.io/badge/License-BSD%203--Clause-blue.svg)](LICENSE)
[![Data: ODbL](https://img.shields.io/badge/Data-ODbL-brightgreen.svg)](https://opendatacommons.org/licenses/odbl/)

Read the [SimBench](https://simbench.net) benchmark grid dataset and convert it to
[PowerModels.jl](https://github.com/lanl-ansi/PowerModels.jl) network data.

SimBench is a set of German EHV/HV/MV/LV benchmark grids with matched load and generation
time series, developed by University of Kassel, TU Dortmund, RWTH Aachen and Fraunhofer
IEE. This package is a Julia port of the [reference
implementation](https://github.com/e2nIEE/simbench), which targets pandapower.

> [!WARNING]
> **Work in progress — phase 1 of 8.** Package skeleton and dataset location only.
> Reading grids and converting them to PowerModels is not implemented yet.
> See [`PLAN.md`](PLAN.md) for the roadmap.

## Status

| Phase | | |
|---|---|---|
| 1 | Skeleton, CI, dataset location | ✅ |
| 2 | CSV parsing, SimBench codes, `SimBenchGrid` | ⬜ |
| 3 | Subnet extraction by SimBench code | ⬜ |
| 4 | Switch and auxiliary-node resolution | ⬜ |
| 5 | PowerModels conversion (per-unit, taps) | ⬜ |
| 6 | Profiles and study cases | ⬜ |
| 7 | Lazy `Pkg` artifacts for the dataset | ⬜ |
| 8 | Docs, tutorials, General registry | ⬜ |

## Installation

```julia
using Pkg
Pkg.add(url = "https://github.com/langestefan/SimBench.jl")
```

## Dataset

The 378 MB CSV dataset is not bundled. Lazy artifact download arrives in phase 7; until
then point the package at a local copy — the `simbench/networks` directory of a
[`simbench`](https://github.com/e2nIEE/simbench) checkout:

```julia
using SimBench

SimBench.set_data_dir!("/path/to/simbench/simbench/networks")
SimBench.scenario_path(0)          # validated path to the scenario-0 folder
SimBench.available_tables(ans)     # the 17 CSV tables it contains
```

`SIMBENCH_DATA_DIR` works as an environment-variable equivalent; `set_data_dir!` wins over
it. Tests that need the dataset skip themselves when it is not configured.

## Design

Conversion runs in two layers, so that the electrical maths is testable without touching
CSV parsing:

```
CSV files ──▶ SimBenchGrid ──▶ PowerModels data dict ──▶ solve_ac_pf
              (17 DataFrames,   (per-unit, bus/branch/
               SimBench units)   gen/load/shunt)
```

Unlike the Python original, there is no pandapower in the middle. pandapower performs the
per-unit conversion internally in `pd2ppc`; PowerModels expects per-unit input, so that
layer is reimplemented here rather than ported. It is cross-validated against
pandapower's power-flow results — see `PLAN.md` §6.

## License

Code is BSD-3-Clause. The SimBench **dataset** is licensed separately under the
[ODbL](https://opendatacommons.org/licenses/odbl/1.0/) by its original authors and carries
attribution and share-alike obligations. See [`LICENSE`](LICENSE).

## Citing

If you use the SimBench dataset, cite the original project rather than this port:
<https://simbench.net>.
