# SimBench.jl

[![Development documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://langestefan.github.io/SimBench.jl/dev/)

[![Test workflow status](https://github.com/langestefan/SimBench.jl/actions/workflows/Test.yml/badge.svg?branch=main)](https://github.com/langestefan/SimBench.jl/actions/workflows/Test.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/langestefan/SimBench.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/langestefan/SimBench.jl)
[![Lint workflow Status](https://github.com/langestefan/SimBench.jl/actions/workflows/Lint.yml/badge.svg?branch=main)](https://github.com/langestefan/SimBench.jl/actions/workflows/Lint.yml?query=branch%3Amain)
[![Docs workflow Status](https://github.com/langestefan/SimBench.jl/actions/workflows/Docs.yml/badge.svg?branch=main)](https://github.com/langestefan/SimBench.jl/actions/workflows/Docs.yml?query=branch%3Amain)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)
[![Code license: BSD-3](https://img.shields.io/badge/code-BSD--3--Clause-blue.svg)](LICENSE)
[![Data license: ODbL](https://img.shields.io/badge/data-ODbL-brightgreen.svg)](https://opendatacommons.org/licenses/odbl/)

SimBench.jl reads the [SimBench](https://simbench.net) benchmark grid dataset and converts
it to [PowerModels.jl](https://github.com/lanl-ansi/PowerModels.jl) network data, so that
published German benchmark grids can be solved with the Julia power-system stack.

SimBench provides realistic, openly licensed grids with matched load and generation time
series across every voltage level, which makes it useful for:

- Grid planning and expansion studies
- Power flow and optimal power flow benchmarking
- Distributed generation and storage integration
- Time series and study case analysis

> [!WARNING]
> **Work in progress.** Reading a whole scenario into a `SimBenchGrid` works.
> Extracting an individual benchmark grid by SimBench code, and converting to
> PowerModels, are not implemented yet.

## Status

| Feature | Status |
| ------------------------------------------- | ------ |
| Dataset location and table inventory | ✅ |
| CSV parsing, SimBench codes, `SimBenchGrid` | ✅ |
| Grid extraction by SimBench code | ⬜ |
| Switch and auxiliary node resolution | ⬜ |
| PowerModels conversion | ⬜ |
| Profiles and study cases | ⬜ |
| Automatic dataset download | ⬜ |

## Acknowledgement

This package is a Julia port of the reference implementation
[simbench](https://github.com/e2nIEE/simbench), which targets
[pandapower](https://www.pandapower.org). The SimBench dataset and the original Python
package are the work of University of Kassel, TU Dortmund, RWTH Aachen University and
Fraunhofer IEE Kassel. This package reads their data; it does not replace or revalidate it.

## Installation

```julia
using Pkg
Pkg.add(url = "https://github.com/langestefan/SimBench.jl")
```

## Dataset

The SimBench CSV dataset is 378 MB and is not bundled with the package. Automatic download
is not implemented yet, so point the package at a local copy: the `simbench/networks`
directory of a [simbench](https://github.com/e2nIEE/simbench) checkout.

```julia
julia> using SimBench

julia> SimBench.set_data_dir!("/path/to/simbench/simbench/networks")
"/path/to/simbench/simbench/networks"

julia> SimBench.scenario_path(0)
"/path/to/simbench/simbench/networks/1-complete_data-mixed-all-0-sw"

julia> SimBench.available_tables(ans)
17-element Vector{Symbol}:
 :ExternalNet
 :Line
 :Load
 :Node
 ⋮
```

`SIMBENCH_DATA_DIR` works as an environment-variable equivalent; `set_data_dir!` takes
precedence over it. Tests that need the dataset skip themselves when it is not configured.

### Scenarios

| Scenario | Folder | Size | Extra tables |
| -------- | -------------------------------- | ------ | ---------------------------------------- |
| 0 | `1-complete_data-mixed-all-0-sw` | 111 MB | none |
| 1 | `1-complete_data-mixed-all-1-sw` | 133 MB | `Storage`, `StorageProfile`, `DCLineType` |
| 2 | `1-complete_data-mixed-all-2-sw` | 134 MB | `Storage`, `StorageProfile`, `DCLineType` |

Scenario 0 is the present-day grid. Scenarios 1 and 2 project storage and HVDC build-out
onto it, and scenario 2 carries 6,533 storage units, more than it has renewable generators.

Individual benchmark grids are selected from this complete dataset by *SimBench code*, for
example `1-MVLV-urban-all-0-sw`.

## Design

Conversion runs in two layers, so that the electrical model is testable independently of
CSV parsing:

```text
CSV files ──▶ SimBenchGrid ──▶ PowerModels data dict ──▶ solve_ac_pf
              (20 DataFrames,   (per-unit, bus/branch/
               SimBench units)   gen/load/shunt/storage)
```

Unlike the Python original there is no pandapower in the middle. pandapower performs the
per-unit conversion internally in `pd2ppc`, whereas PowerModels expects per-unit input, so
that layer is reimplemented here rather than ported. It is cross-validated numerically
against pandapower's power-flow results.

## License

The package code is BSD-3-Clause. The SimBench **dataset** is licensed separately under the
[ODbL](https://opendatacommons.org/licenses/odbl/1.0/) by its original authors, and using it
carries the ODbL's attribution and share-alike obligations. See [LICENSE](LICENSE).

## How to Cite

If you use SimBench.jl, cite it using the metadata in
[CITATION.cff](https://github.com/langestefan/SimBench.jl/blob/main/CITATION.cff). Please
also cite the SimBench dataset and project itself, which this package only reads. See
[simbench.net](https://simbench.net).

## Contributing

If you want to make contributions of any kind, please first take a look at our
[contributing guide directly on GitHub](docs/src/contributing.md) or the
[contributing page on the website](https://langestefan.github.io/SimBench.jl/dev/contributing/).
