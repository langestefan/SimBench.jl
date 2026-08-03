# Resolving auxiliary nodes and switches into a plain bus topology.
#
# SimBench does not attach branches to buses directly. A branch end sits on its own
# `auxiliary` node, which reaches the real bus through one switch:
#
#     busbar ──switch── auxiliary ──── line/transformer
#
# In the published scenario 0 that accounts for 70408 of 105615 nodes and 72788 of
# 73511 switches. PowerModels has no switch element, so this layer collapses the
# auxiliary nodes away, leaving each branch on real buses and each branch carrying the
# state of the switches at its ends.
#
# The remaining switches join two real buses. Those are the bus couplers inside
# substations, 723 of them in scenario 0.

"""
    Topology

Bus topology of a grid after auxiliary nodes and switches have been resolved.

# Fields
- `buses::Vector{String}`: the node id representing each bus, in Node table order.
- `bus_of::Dict{String, Int}`: every node id, auxiliary ones included, mapped to its bus
  number. Bus numbers index `buses`.
- `members::Vector{Vector{String}}`: node ids collapsed into each bus. A bus with more
  than one member was formed by fusing across closed bus couplers.
- `line_closed::BitVector`: per `Line` row, whether both end switches are closed.
- `line_ends::Vector{Tuple{Bool, Bool}}`: per `Line` row, whether the switch at the
  `nodeA` and `nodeB` end is closed. An end sitting directly on a real bus has no
  switch and counts as closed. In the published scenario 0 every out-of-service line
  is open at exactly one end.
- `trafo_closed::BitVector`: per `Transformer` row, whether both end switches are
  closed.
- `bus_switches::Vector{Tuple{Int, Int, Bool}}`: bus couplers that were not fused, as
  `(bus, bus, closed)`. Empty when `collapse = true`.
- `retyped::Vector{String}`: auxiliary nodes promoted to real buses because they carry
  more than one switch.
"""
struct Topology
    buses::Vector{String}
    bus_of::Dict{String, Int}
    members::Vector{Vector{String}}
    line_closed::BitVector
    line_ends::Vector{Tuple{Bool, Bool}}
    trafo_closed::BitVector
    bus_switches::Vector{Tuple{Int, Int, Bool}}
    retyped::Vector{String}
end

nbuses(t::Topology) = length(t.buses)

function Base.show(io::IO, ::MIME"text/plain", t::Topology)
    fused = count(m -> length(m) > 1, t.members)
    println(io, "Topology with ", length(t.buses), " buses")
    println(io, "  fused across couplers: ", fused)
    println(io, "  auxiliary nodes promoted: ", length(t.retyped))
    println(io, "  lines out of service: ", count(!, t.line_closed))
    println(io, "  transformers out of service: ", count(!, t.trafo_closed))
    print(io, "  unfused bus couplers: ", length(t.bus_switches))
    return
end

Base.show(io::IO, t::Topology) = print(io, "Topology(", length(t.buses), " buses)")

"""
    multi_switch_aux_nodes(node, switch) -> Set{String}

Auxiliary nodes carrying more than one switch.

These are not branch-end helpers but real connection points, so they are treated as
buses. Upstream does the same in `_ensure_single_switch_at_aux_node_and_copy_vm_setp`,
retyping them before auxiliary nodes are removed. Scenario 0 has 2380 of them.
"""
function multi_switch_aux_nodes(node::DataFrame, switch::DataFrame)
    aux = Set(
        id for (id, type) in zip(node.id, node.type) if
            !ismissing(id) && type === "auxiliary"
    )
    counts = Dict{String, Int}()
    for col in (switch.nodeA, switch.nodeB), id in col
        ismissing(id) || id in aux || continue
        counts[id] = get(counts, id, 0) + 1
    end
    return Set(id for (id, n) in counts if n > 1)
end

# --- union-find over buses joined by closed couplers ---------------------------------

function _find(parent::Vector{Int}, i::Int)
    while parent[i] != i
        parent[i] = parent[parent[i]]   # path halving
        i = parent[i]
    end
    return i
end

function _union!(parent::Vector{Int}, a::Int, b::Int)
    ra, rb = _find(parent, a), _find(parent, b)
    ra == rb && return ra
    # Keep the lower index as the representative, so fusion is order-independent.
    ra, rb = minmax(ra, rb)
    parent[rb] = ra
    return ra
end

"""
    resolve_topology(tables; collapse=true, respect_open_switches=false) -> Topology

Collapse auxiliary nodes and switches into a bus topology.

Auxiliary nodes always disappear: each is merged into the bus its switch reaches, and
the switch's state is carried onto the branch instead. What happens to the bus couplers
that join two real buses depends on `collapse`.

# Keywords
- `collapse = true`: fuse buses joined by a coupler into one bus, which is what the
  `no_sw` variant of a SimBench code asks for. With `collapse = false` the buses stay
  separate and the couplers are reported in `bus_switches`, for a caller that wants to
  model them as branches.
- `respect_open_switches = false`: upstream's `generate_no_sw_variant` forces every bus
  coupler closed before fusing, so open couplers are fused too. That is reproduced by
  default. Setting this to `true` fuses only closed couplers, and results then differ
  from pandapower.

  Most open couplers are double-busbar selectors, where a branch can be switched to
  either busbar and is currently on one of them: 2370 of the 2380 promoted nodes in
  scenario 0 carry exactly one closed and one open switch. Fusing them merges the two
  busbars of a station. The effect is smaller than the count suggests, because a
  station's busbars are usually also joined by a closed bus tie, so respecting open
  couplers yields 34498 buses against 34479, a difference of 19.
"""
function resolve_topology(
        tables::Dict{Symbol, DataFrame};
        collapse::Bool = true, respect_open_switches::Bool = false,
    )
    node, switch = tables[:Node], tables[:Switch]
    line, trafo = tables[:Line], tables[:Transformer]

    promoted = multi_switch_aux_nodes(node, switch)
    is_aux = Dict{String, Bool}()
    for (id, type) in zip(node.id, node.type)
        ismissing(id) && continue
        is_aux[id] = (type === "auxiliary") && !(id in promoted)
    end

    # Real buses keep Node table order, so bus numbering is stable.
    buses = [id for id in node.id if !ismissing(id) && !is_aux[id]]
    index_of = Dict(id => i for (i, id) in enumerate(buses))

    # Each auxiliary node reaches exactly one real bus through exactly one switch.
    aux_bus = Dict{String, Int}()
    aux_closed = Dict{String, Bool}()
    couplers = Tuple{Int, Int, Bool}[]
    for i in 1:nrow(switch)
        a, b = switch.nodeA[i], switch.nodeB[i]
        (ismissing(a) || ismissing(b)) && continue
        closed = !ismissing(switch.cond[i]) && switch.cond[i] == 1
        aux_a = get(is_aux, a, false)
        aux_b = get(is_aux, b, false)

        if aux_a && aux_b
            throw(
                ArgumentError(
                    "switch \"$(switch.id[i])\" joins two auxiliary nodes, which the " *
                        "SimBench format does not allow",
                ),
            )
        elseif aux_a || aux_b
            aux, real = aux_a ? (a, b) : (b, a)
            haskey(index_of, real) || throw(
                ArgumentError("switch \"$(switch.id[i])\" references unknown node \"$real\""),
            )
            aux_bus[aux] = index_of[real]
            aux_closed[aux] = closed
        else
            (haskey(index_of, a) && haskey(index_of, b)) || throw(
                ArgumentError("switch \"$(switch.id[i])\" references an unknown node"),
            )
            push!(couplers, (index_of[a], index_of[b], closed))
        end
    end

    # Fuse across couplers, if asked. Upstream ignores the open ones' state.
    parent = collect(1:length(buses))
    if collapse
        for (a, b, closed) in couplers
            (closed || !respect_open_switches) && _union!(parent, a, b)
        end
    end

    # Renumber the surviving representatives to a dense 1:n.
    roots = sort!(unique(_find(parent, i) for i in 1:length(buses)))
    dense = Dict(r => i for (i, r) in enumerate(roots))
    final_of_old = [dense[_find(parent, i)] for i in 1:length(buses)]

    final_buses = [buses[r] for r in roots]
    members = [String[] for _ in roots]
    bus_of = Dict{String, Int}()
    for (i, id) in enumerate(buses)
        b = final_of_old[i]
        bus_of[id] = b
        push!(members[b], id)
    end
    for (aux, old) in aux_bus
        bus_of[aux] = final_of_old[old]
    end

    remaining = if collapse
        Tuple{Int, Int, Bool}[]
    else
        [(final_of_old[a], final_of_old[b], c) for (a, b, c) in couplers]
    end

    # A branch is in service when the switches at both of its ends are closed. An end
    # sitting directly on a real bus has no switch and counts as closed.
    end_closed(id) = ismissing(id) ? false : get(aux_closed, id, true)
    line_ends = [
        (end_closed(line.nodeA[i]), end_closed(line.nodeB[i])) for i in 1:nrow(line)
    ]
    line_closed = BitVector(a && b for (a, b) in line_ends)
    trafo_closed = BitVector(
        end_closed(trafo.nodeHV[i]) && end_closed(trafo.nodeLV[i]) for i in 1:nrow(trafo)
    )

    return Topology(
        final_buses, bus_of, members, line_closed, line_ends, trafo_closed, remaining,
        sort!(collect(promoted)),
    )
end

"""
    resolve_topology(grid; kwargs...) -> Topology

Resolve the topology of a [`SimBenchGrid`](@ref).

`collapse` defaults to the switch variant the grid's SimBench code asks for: a `no_sw`
code collapses the bus couplers, an `sw` code keeps them.
"""
function resolve_topology(grid::SimBenchGrid; collapse::Bool = !grid.code.breaker_rep, kwargs...)
    return resolve_topology(grid.tables; collapse, kwargs...)
end

"""
    bus_of(topology, node_id) -> Int

Bus number carrying `node_id`. Throws `KeyError` for an unknown node.
"""
bus_of(t::Topology, node_id::AbstractString) = t.bus_of[node_id]
