# Plotting

The converted grids plot directly with
[PowerPlots.jl](https://github.com/WISPO-POP/PowerPlots.jl), and SimBench ships real
geographic coordinates for every node, so the plots show the networks as they are laid
out on the ground rather than through a layout algorithm.

[`SimBench.attach_coordinates!`](@ref) bridges the two: it writes the `xcoord_1` and
`ycoord_1` keys PowerPlots reads, placing each bus at its position from the
`Coordinates` table with generators, loads and storage alongside, and normalises the
raw longitude and latitude into a plot-friendly unit box. `powerplot(data; fixed =
true)` then renders the network without recomputing a layout.

The plots on this page are generated when the documentation is built.

## A low voltage grid at the evening peak

Reading the rural low voltage grid, setting it to a winter evening with
[`apply_profile!`](@ref SimBench.apply_profile!), and solving:

```@example plots
using SimBench, PowerModels, PowerPlots, VegaLite, Dates
PowerModels.silence()

grid = read_grid("1-LV-rural1--0-no_sw"; cache = true)
data = powermodels_data(grid)
SimBench.attach_coordinates!(data, grid)

profiles = absolute_profiles(grid)
apply_profile!(data, profiles, DateTime(2016, 1, 15, 18, 0))

result = compute_ac_pf(data)
result["termination_status"]
```

`compute_ac_pf` returns bus voltages and generator outputs; writing them back into the
case and deriving the branch flows gives the plot something to show. Flows in MW read
better on a legend than per unit:

```@example plots
update_data!(data, result["solution"])
update_data!(data, calc_branch_flow_ac(data))
for br in values(data["branch"])
    br["p_mw"] = abs(br["pf"]) * data["baseMVA"]
end
nothing # hide
```

Buses are shaded by voltage magnitude, branches by their loading, and the arrows point
along the power flow, out from the transformer at the top into the four feeders:

```@example plots
p = powerplot(
    data;
    fixed = true,
    bus = (:data => :vm, :data_type => :quantitative, :size => 250),
    branch = (
        :data => :p_mw, :data_type => :quantitative, :show_flow => true,
        :flow_arrow_size_range => [450, 450],
        :color => ["#cbd5e1", "#e6550d"],
    ),
    load = (:size => 40),
    gen = (:size => 60),
    height = 650, width = 650,
)
save("lv_vm.svg", p)
nothing # hide
```

![The rural low voltage grid at the winter evening peak](lv_vm.svg)

## A medium voltage grid

The rural medium voltage grid draws its feeders as loops through the countryside;
the geographic coordinates make them visible as such. The base case solves without
touching the profiles:

```@example plots
grid_mv = read_grid("1-MV-rural--0-no_sw"; cache = true)
data_mv = powermodels_data(grid_mv)
SimBench.attach_coordinates!(data_mv, grid_mv)

result = compute_ac_pf(data_mv)
update_data!(data_mv, result["solution"])
update_data!(data_mv, calc_branch_flow_ac(data_mv))
for br in values(data_mv["branch"])
    br["p_mw"] = abs(br["pf"]) * data_mv["baseMVA"]
end

p = powerplot(
    data_mv;
    fixed = true,
    bus = (:data => :vm, :data_type => :quantitative, :size => 90),
    branch = (
        :data => :p_mw, :data_type => :quantitative, :show_flow => true,
        :flow_arrow_size_range => [200, 200],
        :color => ["#cbd5e1", "#e6550d"],
    ),
    load = (:size => 15),
    gen = (:size => 25),
    height = 800, width = 800,
)
save("mv_flow.svg", p)
nothing # hide
```

![The rural medium voltage grid](mv_flow.svg)

The heavily loaded branches at the feeder heads stand out in orange, and every load
along the loops appears at its geographic position. Under the default
`pq_as = :load`, renewable generators are represented as negative loads, so they show
with the load markers; convert with `pq_as = :gen` to plot them as generators.

The plots are interactive when displayed in a notebook or with an SVG-capable
`display`; hovering shows each component's data. See the
[PowerPlots documentation](https://wispo-pop.github.io/PowerPlots.jl/stable/) for the
full styling vocabulary.
