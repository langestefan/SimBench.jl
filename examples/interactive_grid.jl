# The same solved SimBench grids as `plot_grid.jl`, but interactive: pick the grid and the
# routing algorithm from the menus below the plot, and drag the buses around.
#
# Run with:  julia --project=examples examples/interactive_grid.jl
#
#   * drag a bus with the left mouse button to place it by hand
#   * drag from empty space to rubber-band a group of buses; they are ringed in blue and
#     move together as one when any of them is dragged
#   * shift- or control-click a bus to add or remove it from the selection by hand
#   * right-click a bus to release just that pin
#   * press `r` to relax the layout — pinned buses stay put, the rest settle around them
#   * press `u` to release every pinned bus
#   * pick a grid from the left menu and a routing algorithm from the right one
#
# The first run spends a while compiling GLMakie, and each grid is read, converted and
# solved the first time it is selected; both are then cached, so going back to a grid is
# immediate.

using Dates
using GLMakie
using NetworkLayout
using PowerModels
using PowerPlotsMakie
using SimBench

PowerModels.silence()

# The grids on the menu. Any of the 246 published codes works; these span the voltage
# levels and both switch variants without asking for a grid so large that reading it holds
# up the window.
# Makie reads a menu option as (label, value) only when it is a 2-tuple; a `label => value`
# pair is handed back whole, label and all.
const CASES = [
    ("LV rural", "1-LV-rural1--0-no_sw"),
    ("LV urban", "1-LV-urban6--0-no_sw"),
    ("MV rural", "1-MV-rural--0-no_sw"),
    ("MV urban", "1-MV-urban--0-no_sw"),
    ("MV commercial (switches kept)", "1-MV-comm--0-sw"),
    ("HV mixed", "1-HV-mixed--0-no_sw"),
]

# A winter evening: the load profiles peak and the photovoltaic profiles are at zero.
const PEAK = DateTime(2016, 1, 15, 18, 0)

"""
Read one grid, set it to the evening peak, solve it, and build everything the plot needs.

The geographic positions are built here rather than left to the layout. `powerplot` would
find the bus coordinates by itself and pin them, but the injections would still be placed
by the layout, which spaces its free vertices about one unit apart while these coordinates
are normalised into a unit box: the generators and loads would be flung out well beyond
the grid. `attach_coordinates!` has already put every generator, load and storage marker
just off its own bus, so reading the whole position vector back out of the case keeps the
drawing on one scale. Vertex `i` is `net.vertices[i]`, which is all the ordering that
takes.
"""
function prepare(code)
    grid = read_grid(code; cache = true)
    data = powermodels_data(grid)
    SimBench.attach_coordinates!(data, grid)

    profiles = absolute_profiles(grid)
    apply_profile!(data, profiles, PEAK)

    # `compute_ac_pf` is PowerModels' native Newton-Raphson: no optimizer, and it starts
    # from the `vm_start`/`va_start` values the conversion seeds, which is what carries it
    # through the transformer phase shifts.
    result = compute_ac_pf(data)
    update_data!(data, result["solution"])
    update_data!(data, calc_branch_flow_ac(data))

    # Loading as a fraction of the thermal rating reads better on a colorbar than either
    # the flow in MW or the per-unit value, since it puts every voltage level on one scale.
    for br in values(data["branch"])
        s = hypot(br["pf"], br["qf"])
        br["loading"] = br["rate_a"] > 0 ? s / br["rate_a"] : 0.0
    end

    net = powernetwork(data)
    positions = [_position(data, ref) for ref in net.vertices]
    vms = [bus["vm"] for bus in values(data["bus"])]
    return (; code, data, net, positions, band = extrema(vms))
end

function _position(data, ref)
    p = node_coordinates(data, ref.component, ref.id)
    p === nothing || return Point2f(p)
    # A component the Coordinates table does not place, a shunt say, sits on its bus.
    ref.component === :bus && return Point2f(0, 0)
    b = node_coordinates(data, :bus, string(injection_bus(data, ref.component, ref.id)))
    return b === nothing ? Point2f(0, 0) : Point2f(b)
end

# Reading and solving a grid takes a moment; a grid already looked at does not pay it
# twice.
const PREPARED = Dict{String, Any}()
prepared(code) = get!(() -> prepare(code), PREPARED, code)

# ---------------------------------------------------------------------------------------
# Routing algorithms
#
# Each option is a (layout, relaxer) pair: what to pass to the plot's `layout` attribute,
# and the constructor `r` should rebuild with afterwards. `:geographic` is this package's
# own contribution to the list, and stands for the position vector `prepare` built; the
# rest are the algorithms PowerPlotsMakie routes with, which ignore the coordinates and
# draw the grid as a graph.
# ---------------------------------------------------------------------------------------

const LAYOUTS = [
    ("geographic", (:geographic, NetworkLayout.Stress)),
    ("auto (detect)", (:auto, NetworkLayout.Stress)),
    ("radial (Buchheim)", (:radial, NetworkLayout.Stress)),
    ("stress", (:stress, NetworkLayout.Stress)),
    ("spring", (NetworkLayout.Spring(), NetworkLayout.Spring)),
    ("SFDP", (NetworkLayout.SFDP(), NetworkLayout.SFDP)),
]

# ---------------------------------------------------------------------------------------

case = prepared(CASES[3][2])     # the rural medium voltage grid, to start with

fig = Figure(size = (1050, 850))
ax = Axis(
    fig[1, 1];
    title = "$(case.code) at the $(PEAK) evening peak",
    subtitle = "buses coloured by voltage magnitude, branches by loading",
    # The longitudes are corrected for the latitude on the way in, so under the geographic
    # routing equal steps in x and y are equal distances on the ground.
    aspect = DataAspect(),
)
hidedecorations!(ax)
hidespines!(ax)

plt = powerplot!(
    ax,
    case.net;
    layout = case.positions,
    node_size = 8,
    # `true` is shorthand for `Field(:pf)`: active power leaving the from-bus, which is
    # what `update_data!` has just written into every branch.
    flow = true,
    flow_size = (4.0, 12.0),
    components = Dict(
        :bus => (color = Field(:vm), colormap = :viridis),
        :branch => (color = Field(:loading), colormap = :inferno, width = 2.5),
        # Under the default `pq_as = :load`, renewable generators are converted as
        # negative loads, so the load markers cover both; `gen` here is the external grid
        # infeed. Convert with `pq_as = :gen` to separate them.
        :gen => (color = :seagreen, marker = :rect, size = 12),
        :load => (color = :crimson, marker = :utriangle, size = 6),
    ),
)

interaction = interactive!(ax, plt)

# The legend is rebuilt whenever the grid changes, so it gets a cell of its own to be
# emptied into. One entry per flat-coloured component, one colorbar per field being
# coloured by; Makie builds neither on its own.
legendbox = fig[1, 2] = GridLayout()
powerlegend!(legendbox[1, 1], plt)

controls = fig[2, 1] = GridLayout(tellwidth = false)
Label(controls[1, 1], "grid:"; halign = :right)
case_menu = Menu(controls[1, 2]; options = CASES, default = 3, width = 240)
Label(controls[1, 3], "routing algorithm:"; halign = :right)
layout_menu = Menu(controls[1, 4]; options = LAYOUTS, default = 1, width = 200)

"""
Re-route the network with the algorithm the menu is showing.

Choosing an algorithm re-routes from scratch: every pin is released and the network is laid
out afresh, which is what a menu saying "lay this out differently" should do. `r` stays
incremental — it relaxes from wherever the buses are now, holding the pins — and follows
the menu for the algorithms that can hold one. Buchheim cannot: it has no notion of an
initial position or a fixed node, so a tree layout leaves `r` relaxing with Stress.
"""
function route!()
    layout, relaxer = layout_menu.selection[]
    unpin_all!(interaction.state)
    deselect_all!(interaction.state)
    plt.pin = Int[]
    plt.layout = layout === :geographic ? case.positions : layout
    interaction.algorithm = relaxer
    # The interaction is still holding the positions from the old layout until told
    # otherwise; without this the next drag would snap the network back to them.
    resync!(interaction)
    autolimits!(ax)
    return nothing
end

"""
Put another grid on the axis.

Everything the recipe draws is derived from its `network` argument, so handing it a new one
restyles and re-routes the whole plot in place: no second `powerplot!`, and the interaction
keeps working. The layout is stood down to `:stress` first because a position vector is
checked against the vertex count, and the outgoing one belongs to the outgoing grid.
"""
function show_case!(code)
    global case = prepared(code)
    plt.layout = :stress
    plt.network = case.net
    route!()
    empty!(legendbox)
    powerlegend!(legendbox[1, 1], plt)
    ax.title = "$(case.code) at the $(PEAK) evening peak"
    @info "grid drawn" code buses = length(case.data["bus"]) voltage_band = case.band
    return nothing
end

on(m -> show_case!(m), case_menu.selection)
on(_ -> route!(), layout_menu.selection)

screen = display(fig)

if !isinteractive()
    @info "Pick a grid and a routing algorithm; drag buses, r relaxes, u unpins. \
        Close the window to exit."
    wait(screen)
end
