# Tutorial

This tutorial walks through the package end to end: picking a benchmark grid,
reading it, converting it to PowerModels network data, solving a power flow, and
stepping through the time series and study cases. Every code block on this page is
executed when the documentation is built, so the outputs are real.

## Installation

The package is not registered yet, so install it by URL. PowerModels is not a
dependency of SimBench.jl; add it to your own environment to solve the converted
grids.

```julia
using Pkg
Pkg.add(url = "https://github.com/langestefan/SimBench.jl")
Pkg.add("PowerModels")
```

## Picking a grid

Every benchmark grid is named by a *SimBench code* of the form
`version-levels-type-grid-scenario-switches`. For example, `1-MV-rural--0-no_sw` is
the rural medium-voltage grid in scenario 0, with switch buses collapsed, and
`1-MVLV-urban-all-0-sw` is the urban medium-voltage grid together with all of its
low-voltage grids, keeping the switches. Scenario 0 is the present-day grid;
scenarios 1 and 2 project storage and HVDC build-out onto it.

The full published code space is enumerable, with keywords to narrow it down:

```@example tutorial
using SimBench

SimBench.all_simbench_codes(
    hv_level = "MV", lv_level = "", scenario = 0, all_data = false,
)
```

## Reading a grid

[`SimBench.read_grid`](@ref) takes a code and returns the grid's CSV tables as
`DataFrame`s, in the dataset's own units. The dataset downloads itself on first use
as a lazy artifact, so this call fetches about 88 MB once and reuses it afterwards.

```@example tutorial
grid = SimBench.read_grid("1-MV-rural--0-no_sw")
```

The tables are indexed by name and reference each other by id strings:

```@example tutorial
using DataFrames

first(grid[:Load][!, [:id, :node, :profile, :pLoad, :qLoad]], 5)
```

## Converting to PowerModels

[`SimBench.powermodels_data`](@ref) turns the grid into a PowerModels network data
dictionary: per unit, angles in radians, ready to solve. Auxiliary nodes and
switches are resolved into a bus topology on the way, following the code's `no_sw`
or `sw` variant.

```@example tutorial
data = SimBench.powermodels_data(grid)

(buses = length(data["bus"]), branches = length(data["branch"]),
    loads = length(data["load"]), gens = length(data["gen"]))
```

## Solving a power flow

The dictionary works with both of PowerModels' power flow paths. The native
Newton-Raphson needs no extra solver package:

```@example tutorial
using PowerModels
PowerModels.silence()

result = compute_ac_pf(data)
result["termination_status"]
```

The solution is keyed like the data. Voltage magnitudes across the grid:

```@example tutorial
vms = [bus["vm"] for bus in values(result["solution"]["bus"])]
extrema(vms)
```

The conversion seeds every bus with a starting voltage the solver can converge
from, accounting for transformer phase shifts; without it no solver reaches the
solution, since the Dyn5 transformers put parts of the grid 150 degrees away from
a flat start.

## Stepping through the year

SimBench ships a year of 15-minute profiles in relative units.
[`SimBench.absolute_profiles`](@ref) scales them by each element's base power, giving
one column per element in MW and MVAr:

```@example tutorial
profiles = SimBench.absolute_profiles(grid)

profiles[(:Load, :pLoad)][1:4, 1:4]
```

[`SimBench.apply_profile!`](@ref) sets the converted case to one time step, taken as
a row number or a timestamp. Here is the grid on a winter evening:

```@example tutorial
using Dates

SimBench.apply_profile!(data, profiles, DateTime(2016, 1, 15, 18, 0))
result = compute_ac_pf(data)
extrema(bus["vm"] for bus in values(result["solution"]["bus"]))
```

A time series study is just a loop. The voltage band of the first day, solved at
every quarter hour:

```@example tutorial
band = map(1:96) do t
    SimBench.apply_profile!(data, profiles, t)
    r = compute_ac_pf(data)
    extrema(bus["vm"] for bus in values(r["solution"]["bus"]))
end

(vm_min = minimum(first, band), vm_max = maximum(last, band))
```

## Study cases

Each grid also defines six study cases: `hL` and `n1` at full load without
renewable infeed, `hW` and `hPV` at full load with high wind or solar, and `lW` and
`lPV` at low load with the same infeed.
[`SimBench.apply_study_case!`](@ref) scales the case to one of them, always starting
from the grid's base values:

```@example tutorial
cases = grid[:StudyCases][!, "Study Case"]

DataFrame(
    map(cases) do case
        SimBench.apply_study_case!(data, grid, case)
        r = compute_ac_pf(data)
        lo, hi = extrema(bus["vm"] for bus in values(r["solution"]["bus"]))
        (case = case, vm_min = round(lo, digits = 4), vm_max = round(hi, digits = 4))
    end
)
```

The low-load cases lift the voltages: with little demand, the renewable infeed
pushes power up through the feeders.

## Where to go from here

- [`SimBench.powermodels_data`](@ref) documents the conversion keywords: `pq_as`
  for how renewables are represented, `dc_as` for the HVDC links and `storage_as`
  for the storage units of scenarios 1 and 2, and `single_reference` for grids with
  several slacks.
- A local copy of the dataset can be used instead of the artifact via
  [`SimBench.set_data_dir!`](@ref) or the `SIMBENCH_DATA_DIR` environment variable.
- The [API reference](api.md) covers the full surface, including the lower-level
  reading, extraction and topology layers.
