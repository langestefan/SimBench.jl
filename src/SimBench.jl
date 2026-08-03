"""
    SimBench

Read the [SimBench](https://simbench.net) benchmark grid dataset and convert it to
[PowerModels.jl](https://github.com/lanl-ansi/PowerModels.jl) network data.

SimBench is a set of German EHV/HV/MV/LV benchmark grids with matched load and generation
time series, published by University of Kassel, TU Dortmund, RWTH Aachen and Fraunhofer
IEE. This package is a Julia port of the reference implementation at
<https://github.com/e2nIEE/simbench>, which targets pandapower.

The dataset itself is licensed under the ODbL; this package's code is BSD-3-Clause.

!!! note "Work in progress"
    Reading any published benchmark grid, converting it to PowerModels network data,
    and applying profiles and study cases all work. The package is not registered yet
    and the API may still change.

# Dataset location

The dataset downloads itself on first use as a lazy `Pkg` artifact. To use a local copy
instead:

```julia
SimBench.set_data_dir!("/path/to/simbench/simbench/networks")
```

or set the `SIMBENCH_DATA_DIR` environment variable to the same directory.
"""
module SimBench

using Artifacts: @artifact_str
using CSV: CSV
using DataFrames: DataFrame, Not, nrow
using Dates: DateTime, @dateformat_str
using LazyArtifacts: LazyArtifacts

export SimBenchGrid, SimBenchCode, all_simbench_codes, read_grid, powermodels_data,
    absolute_profiles, apply_profile!, apply_study_case!

include("schema.jl")
include("data_source.jl")
include("codes.jl")
include("voltlvl.jl")
include("io.jl")
include("extract.jl")
include("grid.jl")
include("switches.jl")
include("powermodels.jl")
include("profiles.jl")

end # module
