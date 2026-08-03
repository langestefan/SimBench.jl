# Converting a resolved SimBench grid into PowerModels network data.
#
# This is the one layer with no counterpart in the reference implementation. pandapower
# keeps grids in engineering units and converts to per unit internally when it builds a
# power flow; PowerModels expects per-unit input, so the conversion is done here.
#
# Conventions follow pandapower's pd2ppc so that results can be compared against it:
#
#   * A transformer's series impedance is referred to its low-voltage side, with the
#     high-voltage bus as the branch's from bus.
#   * The magnetising admittance is split evenly between the two ends, matching
#     pandapower's use of the MATPOWER charging-susceptance columns.
#   * `tap` is the off-nominal ratio (vn_hv/vn_lv) / (base_kv_hv/base_kv_lv), with the
#     tap position applied to whichever winding the type nominates.

"""Default system base power in MVA."""
const DEFAULT_BASE_MVA = 100.0

"""Bus type codes used by MATPOWER and PowerModels."""
const BUS_PQ, BUS_PV, BUS_REF = 1, 2, 3

"""
Default voltage angle difference limit on a branch, in degrees.

Wide enough not to bind, following the common MATPOWER practice of +/-360. SimBench
specifies no angle limits, and a tight limit is not merely conservative here: a Dyn5
transformer carries a 150 degree phase shift, so any bound below that makes the case
infeasible.
"""
const DEFAULT_ANGLE_LIMIT = 360.0

# Values large enough to stand in for "unconstrained" in MW / MVAr.
const UNLIMITED_P = 1.0e6
const UNLIMITED_Q = 1.0e6

_val(x, default) = ismissing(x) ? default : x

"""
    powermodels_data(grid; kwargs...) -> Dict{String, Any}

Convert a [`SimBenchGrid`](@ref) to a PowerModels network data dictionary.

The result is in the form PowerModels works in: powers per unit on `baseMVA`, voltage
magnitudes per unit, angles in radians, and branch impedances per unit on `baseMVA` and
the bus base voltages. `per_unit` is `true`, so PowerModels leaves it alone.

# Keywords
- `baseMVA = 100.0`: system base power.
- `topology`: a [`Topology`](@ref) to use instead of resolving one. Resolving follows the
  grid's SimBench code, so a `no_sw` code collapses bus couplers and an `sw` code keeps
  them as zero-impedance branches.
- `coupler_impedance = 1.0e-5`: per-unit series reactance given to a bus coupler that was
  not fused. Only used for an `sw` grid; PowerModels has no switch element, and an exactly
  zero impedance makes the system singular.
- `pq_as = :load`: how to represent elements whose `calc_type` is `pq`, which in the
  published data means every renewable generator. `:load` makes each one a negative load,
  matching what pandapower does with a static generator and keeping all generators on PV
  or slack buses, as `PowerModels.compute_ac_pf` requires. `:gen` instead emits a
  generator with `pmin == pmax`, which suits optimal power flow but leaves generators on
  PQ buses.
- `angle_limit = 360.0`: voltage angle difference limit on every branch, in degrees.
  Must exceed the largest transformer phase shift, which is 150 degrees for the Dyn5
  units throughout the low and medium voltage grids, or the case is infeasible.
- `seed_angles = true`: give each bus a starting angle that accounts for the transformer
  phase shifts between it and the reference bus. Without this the case is sound but no
  solver reaches its solution, since everything starts 150 degrees away.
- `single_reference = false`: when true, keeps one reference bus per connected component
  and demotes any others to PV. SimBench shares balancing duty between several `vavm`
  elements using the `dspf` participation factors, which PowerModels cannot express.
  Leaving this off is faithful and reproduces pandapower on the grids that solve; turning
  it on changes how generation is shared, so results then differ from pandapower.
- Remaining keywords go to [`resolve_topology`](@ref).

# Examples
```julia
using PowerModels
grid = SimBench.read_grid("1-LV-rural1--0-no_sw")
data = SimBench.powermodels_data(grid)
result = PowerModels.solve_ac_pf(data, Ipopt.Optimizer)
```
"""
function powermodels_data(
        grid::SimBenchGrid;
        baseMVA::Real = DEFAULT_BASE_MVA,
        topology::Union{Nothing, Topology} = nothing,
        coupler_impedance::Real = 1.0e-5,
        pq_as::Symbol = :load,
        angle_limit::Real = DEFAULT_ANGLE_LIMIT,
        seed_angles::Bool = true,
        single_reference::Bool = false,
        kwargs...,
    )
    pq_as in (:load, :gen) || throw(
        ArgumentError("pq_as must be :load or :gen, got :$pq_as"),
    )
    topo = topology === nothing ? resolve_topology(grid; kwargs...) : topology
    tables = grid.tables

    data = Dict{String, Any}(
        "name" => string(grid.code),
        "baseMVA" => Float64(baseMVA),
        "per_unit" => true,
        "source_type" => "simbench",
        "source_version" => string(DATASET_RELEASE),
        "bus" => Dict{String, Any}(),
        "branch" => Dict{String, Any}(),
        "gen" => Dict{String, Any}(),
        "load" => Dict{String, Any}(),
        "shunt" => Dict{String, Any}(),
        "storage" => Dict{String, Any}(),
        "switch" => Dict{String, Any}(),
        "dcline" => Dict{String, Any}(),
    )

    base_kv = _add_buses!(data, tables[:Node], topo)
    _add_loads!(data, tables[:Load], topo)
    _add_generation!(data, tables, topo, pq_as)
    _add_lines!(data, tables, topo, base_kv, baseMVA, angle_limit)
    _add_transformers!(data, tables, topo, base_kv, baseMVA, angle_limit)
    _add_couplers!(data, topo, coupler_impedance, angle_limit)
    _add_shunts!(data, tables[:Shunt], topo, base_kv, baseMVA)
    _add_storage!(data, tables[:Storage], topo)
    single_reference && _demote_extra_references!(data)
    seed_angles && _seed_angles!(data)
    _to_per_unit!(data, baseMVA)

    return data
end

"""
Leave one reference bus per connected component, turning the rest into PV buses.

SimBench marks several elements as `vavm` in the upper voltage levels, seven power plants
in the extra-high-voltage grid alone, and shares the balancing duty between them through
the `dspf` participation factors. PowerModels has no distributed slack: fixing voltage
magnitude and angle at every one of them leaves the split between them undetermined, and
the power flow comes back infeasible.

Demoting all but one to PV keeps each element's voltage magnitude setpoint and gives the
balancing duty to a single bus, which is what a solver without a distributed slack needs.
"""
function _demote_extra_references!(data)
    # Component labelling over in-service branches.
    parent = Dict(b["index"] => b["index"] for (_, b) in data["bus"])
    find(i) = (while parent[i] != i; parent[i] = parent[parent[i]]; i = parent[i] end; i)
    for (_, br) in data["branch"]
        br["br_status"] == 1 || continue
        a, b = find(br["f_bus"]), find(br["t_bus"])
        a != b && (parent[max(a, b)] = min(a, b))
    end

    refs = Dict{Int, Vector{Int}}()
    for (_, bus) in data["bus"]
        bus["bus_type"] == BUS_REF || continue
        push!(get!(refs, find(bus["index"]), Int[]), bus["index"])
    end

    demoted = 0
    for (_, buses) in refs
        length(buses) > 1 || continue
        for b in sort(buses)[2:end]
            data["bus"]["$b"]["bus_type"] = BUS_PV
            demoted += 1
        end
    end
    demoted > 0 && @debug "Demoted $demoted reference buses to PV; PowerModels has no " *
        "distributed slack, so one reference per component is kept."
    return data
end

"""
Give every bus a starting voltage angle that accounts for transformer phase shifts.

Without this the whole network starts at the reference angle, which is far from any
solution once a transformer shifts by 150 degrees, as the Dyn5 units throughout the low
and medium voltage grids do. Both `PowerModels.compute_ac_pf` and `solve_ac_pf` fail from
such a start even though the case itself is sound.

Angles are propagated outward from each reference bus over in-service branches,
subtracting each transformer's shift. This is only a starting point; the solver moves it.
"""
function _seed_angles!(data)
    # Adjacency over in-service branches, carrying the shift in the from-to direction.
    neighbours = Dict{Int, Vector{Tuple{Int, Float64}}}()
    for (_, br) in data["branch"]
        br["br_status"] == 1 || continue
        f, t, shift = br["f_bus"], br["t_bus"], br["shift"]
        push!(get!(neighbours, f, Tuple{Int, Float64}[]), (t, -shift))
        push!(get!(neighbours, t, Tuple{Int, Float64}[]), (f, +shift))
    end

    seen = Set{Int}()
    queue = Int[]
    for (_, bus) in data["bus"]
        bus["bus_type"] == BUS_REF || continue
        push!(queue, bus["index"])
        push!(seen, bus["index"])
    end

    head = 1
    while head <= length(queue)
        b = queue[head]
        head += 1
        va = data["bus"]["$b"]["va"]
        for (nb, delta) in get(neighbours, b, ())
            nb in seen && continue
            push!(seen, nb)
            push!(queue, nb)
            data["bus"]["$nb"]["va"] = va + delta
        end
    end

    # PowerModels takes a variable's starting point from the `_start` keys, so setting
    # `va` alone would leave the solver at a flat start regardless.
    for (_, bus) in data["bus"]
        bus["va_start"] = bus["va"]
        bus["vm_start"] = bus["vm"]
    end
    return data
end

"""
Convert the assembled case from MW and degrees to per unit and radians.

Mirrors what `PowerModels.make_per_unit!` would do, so that the returned case is already
in the form PowerModels works in. Emitting it directly rather than leaving the caller to
convert matters because `PowerModels.compute_ac_pf` does not convert for itself, and
silently fails to converge on unconverted data.
"""
function _to_per_unit!(data, baseMVA)
    rescale(x) = x / baseMVA

    for (_, bus) in data["bus"]
        bus["va"] = deg2rad(bus["va"])
        haskey(bus, "va_start") && (bus["va_start"] = deg2rad(bus["va_start"]))
    end
    for (_, load) in data["load"], k in ("pd", "qd")
        load[k] = rescale(load[k])
    end
    for (_, shunt) in data["shunt"], k in ("gs", "bs")
        shunt[k] = rescale(shunt[k])
    end
    for (_, gen) in data["gen"], k in ("pg", "qg", "pmin", "pmax", "qmin", "qmax")
        gen[k] = rescale(gen[k])
    end
    for (_, branch) in data["branch"]
        branch["rate_a"] = rescale(branch["rate_a"])
        for k in ("shift", "angmin", "angmax")
            branch[k] = deg2rad(branch[k])
        end
    end
    for (_, strg) in data["storage"], k in (
            "ps", "qs", "energy", "energy_rating", "charge_rating",
            "discharge_rating", "thermal_rating", "qmin", "qmax", "p_loss", "q_loss",
        )
        strg[k] = rescale(strg[k])
    end

    data["per_unit"] = true
    return data
end

powermodels_data(code; kwargs...) = powermodels_data(read_grid(code); kwargs...)

# --- buses ---------------------------------------------------------------------------

"""Add one PowerModels bus per resolved bus; returns each bus's base voltage in kV."""
function _add_buses!(data, node::DataFrame, topo::Topology)
    row_of = Dict{String, Int}()
    for (i, id) in enumerate(node.id)
        ismissing(id) || (row_of[id] = i)
    end

    n = length(topo.buses)
    base_kv = Vector{Float64}(undef, n)
    for b in 1:n
        # A fused bus takes its data from its representative; members of one bus are at
        # the same voltage level by construction.
        r = row_of[topo.buses[b]]
        base_kv[b] = _val(node.vmR[r], 1.0)
        data["bus"]["$b"] = Dict{String, Any}(
            "bus_i" => b,
            "index" => b,
            "name" => topo.buses[b],
            "bus_type" => BUS_PQ,
            "base_kv" => base_kv[b],
            "vm" => _val(node.vmSetp[r], 1.0),
            "va" => _val(node.vaSetp[r], 0.0),
            "vmin" => _val(node.vmMin[r], 0.8),
            "vmax" => _val(node.vmMax[r], 1.2),
            "source_id" => Any["bus", topo.buses[b]],
        )
    end
    return base_kv
end

# --- loads ---------------------------------------------------------------------------

function _add_loads!(data, load::DataFrame, topo::Topology)
    for i in 1:nrow(load)
        bus = get(topo.bus_of, load.node[i], nothing)
        bus === nothing && continue
        data["load"]["$i"] = Dict{String, Any}(
            "index" => i,
            "load_bus" => bus,
            "pd" => _val(load.pLoad[i], 0.0),
            "qd" => _val(load.qLoad[i], 0.0),
            "status" => 1,
            "name" => load.id[i],
            "source_id" => Any["load", load.id[i]],
        )
    end
    return
end

# --- generation ----------------------------------------------------------------------

"""
Add generators from the ExternalNet, PowerPlant and RES tables, and set the bus types
they imply.

The `calc_type` column decides the role: `vavm` is a slack, holding both magnitude and
angle, `pvm` holds magnitude at a scheduled active power, and `pq` is a fixed injection
that leaves its bus a load bus. Voltage setpoints come from the node, since none of the
element tables carries one.
"""
function _add_generation!(data, tables, topo::Topology, pq_as::Symbol)
    node = tables[:Node]
    vm_of = Dict{String, Float64}()
    va_of = Dict{String, Float64}()
    for i in 1:nrow(node)
        id = node.id[i]
        ismissing(id) && continue
        vm_of[id] = _val(node.vmSetp[i], 1.0)
        va_of[id] = _val(node.vaSetp[i], 0.0)
    end

    idx = 0
    function add!(bus, name, pg, qg, vg, pmin, pmax, qmin, qmax, kind)
        idx += 1
        data["gen"]["$idx"] = Dict{String, Any}(
            "index" => idx,
            "gen_bus" => bus,
            "pg" => pg, "qg" => qg, "vg" => vg,
            "pmin" => pmin, "pmax" => pmax,
            "qmin" => qmin, "qmax" => qmax,
            "mbase" => data["baseMVA"],
            "gen_status" => 1,
            "name" => name,
            "source_id" => Any[kind, name],
            "model" => 2, "ncost" => 0, "cost" => Float64[],
        )
        return idx
    end

    function bus_type!(bus, calc_type)
        current = data["bus"]["$bus"]["bus_type"]
        if calc_type == "vavm"
            data["bus"]["$bus"]["bus_type"] = BUS_REF
        elseif calc_type == "pvm" && current != BUS_REF
            data["bus"]["$bus"]["bus_type"] = BUS_PV
        end
        return
    end

    # External networks: the boundary equivalents, almost always slacks.
    ext = tables[:ExternalNet]
    for i in 1:nrow(ext)
        bus = get(topo.bus_of, ext.node[i], nothing)
        bus === nothing && continue
        calc = _val(ext.calc_type[i], "vavm")
        if calc in ("Ward", "xWard")
            @warn "ExternalNet \"$(ext.id[i])\" has calc_type $calc, which PowerModels " *
                "cannot represent; treated as a slack."
            calc = "vavm"
        end
        bus_type!(bus, calc)
        add!(
            bus, ext.id[i], _val(ext.pExtNet[i], 0.0), _val(ext.qExtNet[i], 0.0),
            vm_of[ext.node[i]], -UNLIMITED_P, UNLIMITED_P, -UNLIMITED_Q, UNLIMITED_Q,
            "ext_grid",
        )
        if calc == "vavm"
            data["bus"]["$bus"]["va"] = va_of[ext.node[i]]
            data["bus"]["$bus"]["vm"] = vm_of[ext.node[i]]
        end
    end

    # Dispatchable power plants.
    pp = tables[:PowerPlant]
    for i in 1:nrow(pp)
        bus = get(topo.bus_of, pp.node[i], nothing)
        bus === nothing && continue
        calc = _val(pp.calc_type[i], "pvm")
        bus_type!(bus, calc)
        add!(
            bus, pp.id[i], _val(pp.pPP[i], 0.0), _val(pp.qPP[i], 0.0),
            vm_of[pp.node[i]],
            _val(pp.pMin[i], 0.0), _val(pp.pMax[i], _val(pp.pPP[i], 0.0)),
            _val(pp.qMin[i], -UNLIMITED_Q), _val(pp.qMax[i], UNLIMITED_Q),
            "gen",
        )
        if calc == "vavm"
            data["bus"]["$bus"]["vm"] = vm_of[pp.node[i]]
            data["bus"]["$bus"]["va"] = va_of[pp.node[i]]
        end
    end

    # Renewables. Their calc_type is `pq` throughout the published data: a fixed
    # injection rather than something that regulates voltage.
    res = tables[:RES]
    next_load = length(data["load"])
    for i in 1:nrow(res)
        bus = get(topo.bus_of, res.node[i], nothing)
        bus === nothing && continue
        calc = _val(res.calc_type[i], "pq")
        p = _val(res.pRES[i], 0.0)
        q = _val(res.qRES[i], 0.0)

        if calc == "pq" && pq_as === :load
            # A fixed injection is a negative load. This is what pandapower does with a
            # static generator, and it keeps every generator on a PV or slack bus, which
            # PowerModels' Newton-Raphson power flow requires.
            next_load += 1
            data["load"]["$next_load"] = Dict{String, Any}(
                "index" => next_load,
                "load_bus" => bus,
                "pd" => -p, "qd" => -q,
                "status" => 1,
                "name" => res.id[i],
                "source_id" => Any["sgen", res.id[i]],
            )
        else
            bus_type!(bus, calc)
            add!(
                bus, res.id[i], p, q, vm_of[res.node[i]], p, p, q, q, "sgen",
            )
        end
    end
    return
end

# --- branches ------------------------------------------------------------------------

function _branch!(data, i, dict)
    data["branch"]["$i"] = dict
    return
end

"""Add the AC lines. Rows whose type resolves in `DCLineType` are DC and are skipped."""
function _add_lines!(data, tables, topo::Topology, base_kv, baseMVA, angle_limit)
    line, linetype = tables[:Line], tables[:LineType]
    types = Dict(
        id => i for (i, id) in enumerate(linetype.id) if !ismissing(id)
    )
    dc_types = Set(skipmissing(tables[:DCLineType].id))

    n = 0
    for i in 1:nrow(line)
        f = get(topo.bus_of, line.nodeA[i], nothing)
        t = get(topo.bus_of, line.nodeB[i], nothing)
        (f === nothing || t === nothing) && continue

        type = line.type[i]
        if !ismissing(type) && type in dc_types
            continue   # handled as a DC line
        end
        row = get(types, type, nothing)
        row === nothing && throw(
            ArgumentError(
                "line \"$(line.id[i])\" has type \"$type\", which is in neither " *
                    "LineType nor DCLineType",
            ),
        )

        len = _val(line.length[i], 0.0)
        zbase = base_kv[f]^2 / baseMVA
        # b is in microsiemens per kilometre; the total charging is split evenly.
        b_total = _val(linetype.b[row], 0.0) * len * 1.0e-6 * zbase
        imax = _val(linetype.iMax[row], 0.0)

        n += 1
        _branch!(
            data, n,
            Dict{String, Any}(
                "index" => n,
                "f_bus" => f, "t_bus" => t,
                "br_r" => _val(linetype.r[row], 0.0) * len / zbase,
                "br_x" => _val(linetype.x[row], 0.0) * len / zbase,
                "g_fr" => 0.0, "b_fr" => b_total / 2,
                "g_to" => 0.0, "b_to" => b_total / 2,
                "tap" => 1.0, "shift" => 0.0,
                "br_status" => topo.line_closed[i] ? 1 : 0,
                "angmin" => -angle_limit, "angmax" => angle_limit,
                "rate_a" => sqrt(3) * imax * 1.0e-3 * base_kv[f] *
                    _val(line.loadingMax[i], 100.0) / 100,
                "transformer" => false,
                "name" => line.id[i],
                "source_id" => Any["branch", line.id[i]],
            ),
        )
    end
    return n
end

"""
    _t_to_pi(r, x, g, b) -> (r, x, g_shunt, b_shunt)

Convert a transformer's T equivalent to the pi circuit a PowerModels branch describes.

A transformer's magnetising branch sits between the two halves of the leakage impedance,
which a branch cannot express directly. Splitting the leakage evenly and applying a
star-delta transform moves it to the two ends, which is what pandapower does by default
(`trafo_model = "t"`). Because the split is even the result is symmetric, so both ends
carry the same shunt.

With no magnetising branch the transform is undefined, and the impedance passes through.
"""
function _t_to_pi(r, x, g, b)
    (g == 0 && b == 0) && return r, x, 0.0, 0.0
    half = complex(r, x) / 2
    zc = 1 / complex(g, b)
    zsum = half * half + 2 * half * zc
    zab = zsum / zc            # series impedance of the pi circuit
    yf = half / zsum           # shunt admittance at each end
    return real(zab), imag(zab), real(yf), imag(yf)
end

"""
Add the two-winding transformers.

The series impedance is referred to the low-voltage side, matching pandapower, and the
T circuit is converted to a pi circuit by [`_t_to_pi`](@ref).
"""
function _add_transformers!(data, tables, topo::Topology, base_kv, baseMVA, angle_limit)
    trafo, tt = tables[:Transformer], tables[:TransformerType]
    types = Dict(id => i for (i, id) in enumerate(tt.id) if !ismissing(id))
    n = length(data["branch"])

    for i in 1:nrow(trafo)
        f = get(topo.bus_of, trafo.nodeHV[i], nothing)
        t = get(topo.bus_of, trafo.nodeLV[i], nothing)
        (f === nothing || t === nothing) && continue

        row = get(types, trafo.type[i], nothing)
        row === nothing && throw(
            ArgumentError(
                "transformer \"$(trafo.id[i])\" has unknown type \"$(trafo.type[i])\"",
            ),
        )

        sr = _val(tt.sR[row], 1.0)
        vn_hv, vn_lv = _val(tt.vmHV[row], base_kv[f]), _val(tt.vmLV[row], base_kv[t])

        # Tap position moves the rated voltage of whichever winding carries the changer.
        steps = _val(trafo.tappos[i], 0) - _val(tt.tapNeutr[row], 0)
        factor = 1 + steps * _val(tt.dVm[row], 0.0) / 100
        side = lowercase(_val(tt.tapside[row], "hv"))
        vnh = side == "hv" ? vn_hv * factor : vn_hv
        vnl = side == "lv" ? vn_lv * factor : vn_lv

        # Short-circuit impedance, per unit on the system base, referred to the LV side.
        scale = (vnl / base_kv[t])^2 * baseMVA / sr
        vkr = 100 * _val(tt.pCu[row], 0.0) / (sr * 1000)
        z = _val(tt.vmImp[row], 0.0) / 100 * scale
        r = vkr / 100 * scale
        x = sqrt(max(z^2 - r^2, 0.0))

        # Magnetising admittance, from the no-load current and iron losses.
        gm = _val(tt.pFe[row], 0.0) / 1000
        ym = _val(tt.iNoLoad[row], 0.0) / 100 * sr
        bm = -sqrt(max(ym^2 - gm^2, 0.0))
        yscale = base_kv[t]^2 / (baseMVA * vnl^2)
        g, b = gm * yscale, bm * yscale

        # The magnetising branch physically sits between the two leakage half-impedances,
        # which is a T circuit; a branch in PowerModels is a pi circuit. Convert.
        r, x, g_sh, b_sh = _t_to_pi(r, x, g, b)

        n += 1
        _branch!(
            data, n,
            Dict{String, Any}(
                "index" => n,
                "f_bus" => f, "t_bus" => t,
                "br_r" => r, "br_x" => x,
                "g_fr" => g_sh, "b_fr" => b_sh,
                "g_to" => g_sh, "b_to" => b_sh,
                "tap" => (vnh / base_kv[f]) / (vnl / base_kv[t]),
                "shift" => _val(tt.va0[row], 0.0) + steps * _val(tt.dVa[row], 0.0),
                "br_status" => topo.trafo_closed[i] ? 1 : 0,
                "angmin" => -angle_limit, "angmax" => angle_limit,
                "rate_a" => sr * _val(trafo.loadingMax[i], 100.0) / 100,
                "transformer" => true,
                "name" => trafo.id[i],
                "source_id" => Any["branch", trafo.id[i]],
            ),
        )
    end
    return n
end

"""
Add bus couplers that topology resolution left unfused, as near-zero-impedance branches.

Only an `sw` grid has any. PowerModels has no switch element, and a genuinely zero
impedance would make the bus admittance matrix singular, so a small reactance stands in.
"""
function _add_couplers!(data, topo::Topology, coupler_impedance::Real, angle_limit)
    n = length(data["branch"])
    for (k, (f, t, closed)) in enumerate(topo.bus_switches)
        n += 1
        _branch!(
            data, n,
            Dict{String, Any}(
                "index" => n,
                "f_bus" => f, "t_bus" => t,
                "br_r" => 0.0, "br_x" => Float64(coupler_impedance),
                "g_fr" => 0.0, "b_fr" => 0.0, "g_to" => 0.0, "b_to" => 0.0,
                "tap" => 1.0, "shift" => 0.0,
                "br_status" => closed ? 1 : 0,
                "angmin" => -angle_limit, "angmax" => angle_limit,
                "rate_a" => 0.0,
                "transformer" => false,
                "name" => "coupler_$k",
                "source_id" => Any["branch", "coupler_$k"],
            ),
        )
    end
    return n
end

# --- shunts and storage ---------------------------------------------------------------

"""Add shunts. No published SimBench scenario has any, but the format allows them."""
function _add_shunts!(data, shunt::DataFrame, topo::Topology, base_kv, baseMVA)
    for i in 1:nrow(shunt)
        bus = get(topo.bus_of, shunt.node[i], nothing)
        bus === nothing && continue
        # Shunt powers are quoted at the element's own rated voltage.
        ratio = (_val(shunt.vmR[i], base_kv[bus]) / base_kv[bus])^2
        step = _val(shunt.step[i], 1)
        data["shunt"]["$i"] = Dict{String, Any}(
            "index" => i,
            "shunt_bus" => bus,
            "gs" => _val(shunt.p0[i], 0.0) * step / ratio,
            "bs" => -_val(shunt.q0[i], 0.0) * step / ratio,
            "status" => 1,
            "name" => shunt.id[i],
            "source_id" => Any["shunt", shunt.id[i]],
        )
    end
    return
end

"""Add storage units, present in scenarios 1 and 2."""
function _add_storage!(data, storage::DataFrame, topo::Topology)
    for i in 1:nrow(storage)
        bus = get(topo.bus_of, storage.node[i], nothing)
        bus === nothing && continue
        energy_rating = _val(storage.eStore[i], 0.0)
        data["storage"]["$i"] = Dict{String, Any}(
            "index" => i,
            "storage_bus" => bus,
            "ps" => _val(storage.pStor[i], 0.0),
            "qs" => _val(storage.qStor[i], 0.0),
            "energy" => _val(storage.chargeLevel[i], 0.0) * energy_rating,
            "energy_rating" => energy_rating,
            "charge_rating" => abs(_val(storage.pMax[i], 0.0)),
            "discharge_rating" => abs(_val(storage.pMin[i], 0.0)),
            "charge_efficiency" => _val(storage.etaStore[i], 100.0) / 100,
            "discharge_efficiency" => _val(storage.etaStore[i], 100.0) / 100,
            "thermal_rating" => _val(storage.sR[i], 0.0),
            "qmin" => _val(storage.qMin[i], 0.0),
            "qmax" => _val(storage.qMax[i], 0.0),
            "r" => 0.0, "x" => 0.0,
            "p_loss" => 0.0, "q_loss" => 0.0,
            "status" => 1,
            "name" => storage.id[i],
            "source_id" => Any["storage", storage.id[i]],
        )
    end
    return
end
