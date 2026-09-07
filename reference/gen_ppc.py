"""Pin pandapower's internal per-unit values for the selected grids.

Everything is keyed by SimBench name, never by ppc row index, so the Julia side never has
to reproduce pandapower's bus numbering. Buses key on node id and branches on element
name.

Deliberately not emitted:

- RATE_A, which pandapower only fills in OPF mode and is zero here.
- VMAX, VMIN, VM and VA, which are scatter written through the bus lookup, so on a fused
  group the surviving value is whichever member happened to be written last. Those
  legitimately differ from the representative SimBench.jl picks.
"""

from __future__ import annotations

from pandapower.pypower.idx_brch import (
    BR_B,
    BR_G,
    BR_R,
    BR_STATUS,
    BR_X,
    SHIFT,
    TAP,
)
from pandapower.pypower.idx_bus import BASE_KV, BS, BUS_TYPE, GS, PD, QD
from pandapower.pypower.idx_gen import (
    GEN_STATUS,
    PG,
    PMAX,
    PMIN,
    QG,
    QMAX,
    QMIN,
    VG,
)

from common import FIXTURES, boolean, build_ppc, fmt, load_net, targets, write_csv

BUS_HEADER = [
    "node_id",
    "ppc_bus",
    "bus_type",
    "base_kv",
    "pd_mw",
    "qd_mvar",
    "gs_mw",
    "bs_mvar",
]
BRANCH_HEADER = [
    "name",
    "element",
    "from_node",
    "to_node",
    "from_closed",
    "to_closed",
    "br_r",
    "br_x",
    "br_b",
    "br_g",
    "tap",
    "shift_deg",
    "br_status",
]
GEN_HEADER = [
    "name",
    "kind",
    "node_id",
    "pg_mw",
    "qg_mvar",
    "vg_pu",
    "pmax_mw",
    "pmin_mw",
    "qmax_mvar",
    "qmin_mvar",
    "status",
]
DCLINE_HEADER = [
    "name",
    "from_node",
    "to_node",
    "p_mw",
    "loss_mw",
    "loss_percent",
    "vm_from_pu",
    "vm_to_pu",
]


def _switch_states(net, et):
    """Map (element index, bus index) to the switch state at that branch end."""
    switches = net.switch[net.switch.et == et]
    return {(int(r.element), int(r.bus)): bool(r.closed) for r in switches.itertuples()}


def _buses(net, ppc):
    lookup = net._pd2ppc_lookups["bus"]
    rows = []
    for idx, name in net.bus.name.items():
        ppc_bus = int(lookup[idx])
        b = ppc["bus"][ppc_bus]
        rows.append(
            (
                name,
                ppc_bus,
                int(b[BUS_TYPE].real),
                fmt(b[BASE_KV].real),
                fmt(b[PD].real),
                fmt(b[QD].real),
                fmt(b[GS].real),
                fmt(b[BS].real),
            )
        )
    return rows


def _branches(net, ppc):
    names = net.bus.name
    lookups = net._pd2ppc_lookups["branch"]
    rows = []
    for element, frame, et, ends in (
        ("line", net.line, "l", ("from_bus", "to_bus")),
        ("trafo", net.trafo, "t", ("hv_bus", "lv_bus")),
    ):
        if not len(frame):
            continue
        start, _ = lookups[element]
        states = _switch_states(net, et)
        from_col, to_col = ends
        for offset, (idx, row) in enumerate(frame.iterrows()):
            b = ppc["branch"][start + offset]
            f_bus, t_bus = int(row[from_col]), int(row[to_col])
            rows.append(
                (
                    row["name"],
                    element,
                    names[f_bus],
                    names[t_bus],
                    boolean(states.get((int(idx), f_bus), True)),
                    boolean(states.get((int(idx), t_bus), True)),
                    fmt(b[BR_R].real),
                    fmt(b[BR_X].real),
                    fmt(b[BR_B].real),
                    fmt(b[BR_G].real),
                    fmt(b[TAP].real),
                    fmt(b[SHIFT].real),
                    int(b[BR_STATUS].real),
                )
            )
    return rows


def _gens(net, ppc):
    names = net.bus.name
    rows = []
    for kind, frame in (("ext_grid", net.ext_grid), ("gen", net.gen)):
        if not len(frame):
            continue
        lookup = net._pd2ppc_lookups.get(kind)
        if lookup is None:
            continue
        for offset, (idx, row) in enumerate(frame.iterrows()):
            ppc_row = int(lookup[idx]) if hasattr(lookup, "__getitem__") else offset
            g = ppc["gen"][ppc_row]
            rows.append(
                (
                    row["name"],
                    kind,
                    names[int(row["bus"])],
                    fmt(g[PG].real),
                    fmt(g[QG].real),
                    fmt(g[VG].real),
                    fmt(g[PMAX].real),
                    fmt(g[PMIN].real),
                    fmt(g[QMAX].real),
                    fmt(g[QMIN].real),
                    int(g[GEN_STATUS].real),
                )
            )
    return rows


def _dclines(net):
    names = net.bus.name
    rows = []
    for _, row in net.dcline.iterrows():
        rows.append(
            (
                row["name"],
                names[int(row["from_bus"])],
                names[int(row["to_bus"])],
                fmt(row["p_mw"]),
                fmt(row["loss_mw"]),
                fmt(row["loss_percent"]),
                fmt(row["vm_from_pu"]),
                fmt(row["vm_to_pu"]),
            )
        )
    return rows


def generate(code: str) -> dict:
    """Write the per-unit fixtures for `code` and return its manifest fields."""
    print(f"  ppc {code}")
    net = load_net(code)
    ppc = build_ppc(net)

    bus_rows = _buses(net, ppc)
    branch_rows = _branches(net, ppc)
    gen_rows = _gens(net, ppc)

    write_csv(FIXTURES / "ppc" / f"{code}.bus.csv", BUS_HEADER, bus_rows)
    write_csv(FIXTURES / "ppc" / f"{code}.branch.csv", BRANCH_HEADER, branch_rows)
    write_csv(FIXTURES / "ppc" / f"{code}.gen.csv", GEN_HEADER, gen_rows)

    dcline_rows = _dclines(net) if len(net.dcline) else []
    if dcline_rows:
        write_csv(FIXTURES / "ppc" / f"{code}.dcline.csv", DCLINE_HEADER, dcline_rows)

    return {
        "code": code,
        "breaker_rep": "sw" if code.endswith("-sw") else "no_sw",
        "base_mva": fmt(ppc["baseMVA"]),
        "n_pp_bus": len(net.bus),
        "n_ppc_bus": len({r[1] for r in bus_rows}),
        "n_branch": len(branch_rows),
        "n_gen": len(gen_rows),
        "n_dcline": len(dcline_rows),
        "tap_changer_type_applied": boolean(
            len(net.trafo) == 0 or (net.trafo["tap_changer_type"] == "Ratio").all()
        ),
    }


def main() -> None:
    for code in targets()["ppc_codes"]:
        generate(code)


if __name__ == "__main__":
    main()
