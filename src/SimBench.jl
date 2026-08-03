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
    Phase 1 of the port: package skeleton and dataset location. Reading grids and
    converting them to PowerModels is not implemented yet. See `PLAN.md`.

# Dataset location

Until lazy artifact download lands, point the package at a local copy of the dataset:

```julia
SimBench.set_data_dir!("/path/to/simbench/simbench/networks")
```

or set the `SIMBENCH_DATA_DIR` environment variable to the same directory.
"""
module SimBench

include("schema.jl")
include("data_source.jl")

end # module
