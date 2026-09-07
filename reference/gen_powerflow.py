"""Pin pandapower's power flow solution for the selected grids.

Keyed by node id, so the fixture is independent of how either implementation numbers or
fuses buses. Only voltages are recorded: several of these grids have more than one slack,
and how the slack power splits between them is not comparable.
"""

from __future__ import annotations

import math

import pandapower as pp

from common import FIXTURES, RUNPP, boolean, fmt, load_net, targets, write_csv

HEADER = ["node_id", "vm_pu", "va_degree"]


def generate(code: str) -> dict:
    """Write the power flow fixture for `code` and return its manifest fields."""
    print(f"  power flow {code}")
    net = load_net(code)
    pp.runpp(net, **RUNPP)
    assert net.converged, f"{code}: pandapower did not converge"

    rows = []
    nan_buses = 0
    for idx, name in net.bus.name.items():
        vm = float(net.res_bus.vm_pu.get(idx, math.nan))
        va = float(net.res_bus.va_degree.get(idx, math.nan))
        # pandapower writes NaN for a bus its connectivity check found unsupplied.
        # SimBench.jl has no such state, so those rows are dropped and counted instead,
        # which makes a newly unsupplied bus visible on the next regeneration.
        if math.isnan(vm) or math.isnan(va):
            nan_buses += 1
            continue
        rows.append((name, fmt(vm), fmt(va)))

    write_csv(FIXTURES / "powerflow" / f"{code}.bus.csv", HEADER, rows)
    return {
        "pf_converged": boolean(net.converged),
        "pf_buses": len(rows),
        "pf_nan_buses": nan_buses,
    }


def main() -> None:
    for code in targets()["ppc_codes"]:
        generate(code)


if __name__ == "__main__":
    main()
