# Conversion options

[`powermodels_data`](@ref SimBench.powermodels_data) has one job: produce a network
data dictionary that PowerModels solves to the same solution pandapower finds for the
same grid. Its keywords control how elements with no exact PowerModels counterpart are
represented. This page walks through the ones that matter in practice; the docstring
has the full list.

The examples share one grid, read with the scenario cache so the pages of this manual
parse each scenario only once:

```@example conversion
using SimBench

grid = read_grid("1-MV-rural--0-no_sw"; nrows = 1, cache = true)
data = powermodels_data(grid)
data["per_unit"], data["baseMVA"]
```

Powers are per unit on `baseMVA`, angles are in radians, and `per_unit` is already
`true`, so PowerModels uses the case as is.

## Switches: `no_sw` and `sw` codes

Every grid is published in two variants, selected by the code suffix. A `no_sw` code
collapses the bus couplers, fusing the buses they join; an `sw` code keeps them, as
branches with a small series reactance, since PowerModels has no switch element and an
exactly zero impedance would make the system singular:

```@example conversion
sw = powermodels_data(read_grid("1-MV-rural--0-sw"; nrows = 1, cache = true))
couplers = [b for b in values(sw["branch"]) if startswith(b["name"], "coupler")]
(extra_buses = length(sw["bus"]) - length(data["bus"]),
    couplers = length(couplers), br_x = couplers[1]["br_x"])
```

The default `coupler_impedance = 1.0e-6` is the difference between the two models:
voltage agreement with pandapower, which fuses switches ideally, scales linearly with
it, and Newton-Raphson stops converging around `1.0e-7`.

A line that is open at exactly one end stays in service with its open end on a stub
bus, so it still draws charging current from the closed side, again matching
pandapower's switch model.

## Renewables: `pq_as`

Every renewable generator in the published data has `calc_type = pq`, a fixed
injection. `pq_as = :load`, the default, makes each one a negative load. This is what
pandapower does with a static generator, and it keeps every generator on a PV or slack
bus, which `PowerModels.compute_ac_pf` requires:

```@example conversion
(loads = length(data["load"]), gens = length(data["gen"]),
    renewables = sum(l["source_id"][1] == "sgen" for l in values(data["load"])))
```

`pq_as = :gen` instead emits generators pinned with `pmin == pmax`, which suits
optimal power flow, at the price of generators sitting on PQ buses:

```@example conversion
as_gen = powermodels_data(grid; pq_as = :gen)
(loads = length(as_gen["load"]), gens = length(as_gen["gen"]))
```

## HVDC links and storage: `dc_as` and `storage_as`

Scenarios 1 and 2 add HVDC links and storage units. Both need a decision, because
PowerModels' two power flow paths disagree about them: the native Newton-Raphson of
`compute_ac_pf` reads no `dcline` component, and the JuMP model behind `solve_ac_pf`
rejects `storage` outright.

The defaults favour `compute_ac_pf`. Each HVDC link becomes two voltage-controlled
generators, the from side consuming the scheduled power and the to side injecting it
minus losses, which is exactly pandapower's internal representation; storage units
stay `storage` components, whose fixed withdrawals the native solver counts:

```@example conversion
ehv = read_grid("1-EHV-mixed--1-no_sw"; nrows = 1, cache = true)
d = powermodels_data(ehv)
(dc_gens = sum(g["source_id"][1] == "dcline" for g in values(d["gen"])),
    storage = length(d["storage"]))
```

For `solve_ac_pf` or the OPF problems, flip both: `dc_as = :dcline` emits PowerModels
`dcline` components, and `storage_as = :load` turns each storage unit into an
equivalent fixed load:

```@example conversion
d = powermodels_data(ehv; dc_as = :dcline, storage_as = :load)
(dclines = length(d["dcline"]), storage = length(d["storage"]),
    storage_loads = sum(l["source_id"][1] == "storage" for l in values(d["load"])))
```

[`apply_profile!`](@ref SimBench.apply_profile!) follows the elements wherever they
went, matching them through `source_id`.

## The starting point

The conversion seeds every bus with a starting voltage, in the `va_start` and
`vm_start` keys PowerModels reads. Angles account for the transformer phase shifts and
a DC power flow; magnitudes at load buses start at the mean of the controlled-bus
setpoints. This is not cosmetic: the Dyn5 transformers of the low and medium voltage
grids shift by 150 degrees, and the extra-high-voltage grids hold their controlled
buses near 1.09 pu, so from a flat start no solver reaches the solution. Disable it
with `seed_angles = false` to bring your own.

## Fidelity

The conversion is validated against pandapower element by element and by comparing
power flow solutions: every compared grid, across all voltage levels, both switch
variants and all three scenarios, agrees to 1e-10 pu or better. Two things to know
when reproducing that comparison yourself:

- pandapower 3 only applies transformer tap positions when `tap_changer_type` is set,
  which the simbench converter does not do, so set
  `net.trafo["tap_changer_type"] = "Ratio"` first. This package applies the taps, as
  the dataset intends.
- Run `pp.runpp(net, calculate_voltage_angles = True)`; a flat initialisation does not
  converge on the extra-high-voltage grids.
