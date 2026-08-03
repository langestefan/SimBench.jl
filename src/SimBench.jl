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
    Dataset location and the table inventory are in place. Reading grids and converting
    them to PowerModels is not implemented yet.

# Dataset location

Automatic download is not implemented yet, so point the package at a local copy of the
dataset:

```julia
SimBench.set_data_dir!("/path/to/simbench/simbench/networks")
```

or set the `SIMBENCH_DATA_DIR` environment variable to the same directory.
"""
module SimBench

using CSV: CSV
using DataFrames: DataFrame, nrow
using Dates: DateTime, @dateformat_str

include("schema.jl")
include("data_source.jl")
include("codes.jl")
include("voltlvl.jl")
include("io.jl")
include("extract.jl")
include("grid.jl")

end # module
