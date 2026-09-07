"""Regenerate every reference fixture.

This is the entry point. Run it as:

    uv run --project reference reference/generate_all.py

The manifest it writes carries the provenance and the per-code tolerances, so a stale or
wrongly generated reference is visible in the data rather than only in a diff.

Deliberately no generation timestamp: regenerating has to be a no-op on an unchanged
checkout, and a timestamp would make every run produce a diff. Git already records when
the fixtures last changed.
"""

from __future__ import annotations

import sys
from importlib.metadata import version

import gen_codes
import gen_extractions
import gen_powerflow
import gen_ppc
from common import FIXTURES, targets, write_csv

# Measured worst cases across the pinned grids: 5e-15 relative on branch impedance, 3e-14
# absolute on the pi shunt terms, and 8e-12 MW on the aggregated nodal injections. The
# bounds below leave headroom without being meaningless.
#
# Voltages agree less tightly on the sw grids, where SimBench.jl keeps a bus coupler as a
# 1e-6 pu branch and pandapower fuses it ideally. That is a real physical difference of a
# few 1e-6 pu, not a numerical one, so it gets its own bound rather than a blanket
# loosening of everything.
TOLERANCES = {
    "no_sw": {
        "pu_rtol": 1e-12,
        "pu_atol": 1e-12,
        "mw_atol": 1e-9,
        "vm_atol": 1e-6,
        "va_atol": 1e-4,
    },
    "sw": {
        "pu_rtol": 1e-12,
        "pu_atol": 1e-12,
        "mw_atol": 1e-9,
        "vm_atol": 1e-4,
        "va_atol": 1e-2,
    },
}

MANIFEST_HEADER = [
    "code",
    "breaker_rep",
    "base_mva",
    "n_pp_bus",
    "n_ppc_bus",
    "n_branch",
    "n_gen",
    "n_dcline",
    "tap_changer_type_applied",
    "pf_converged",
    "pf_buses",
    "pf_nan_buses",
    "pu_rtol",
    "pu_atol",
    "mw_atol",
    "vm_atol",
    "va_atol",
    "simbench_version",
    "pandapower_version",
    "python_version",
]


def main() -> None:
    print("codes")
    gen_codes.main()

    print("extractions")
    gen_extractions.main()

    provenance = {
        "simbench_version": version("simbench"),
        "pandapower_version": version("pandapower"),
        "python_version": ".".join(str(v) for v in sys.version_info[:3]),
    }

    print("grids")
    rows = []
    for code in targets()["ppc_codes"]:
        fields = gen_ppc.generate(code)
        fields.update(gen_powerflow.generate(code))
        fields.update(TOLERANCES[fields["breaker_rep"]])
        fields.update(provenance)
        rows.append([fields[column] for column in MANIFEST_HEADER])

    write_csv(FIXTURES / "manifest.csv", MANIFEST_HEADER, rows)


if __name__ == "__main__":
    main()
