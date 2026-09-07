"""Shared helpers for generating the pandapower reference fixtures.

Everything that has to be got right exactly once lives here: the two pandapower traps,
the float formatting that lets Julia read the fixtures back bit-exactly, and the digest
definition the Julia tests recompute.
"""

from __future__ import annotations

import csv
import hashlib
import math
import tomllib
from pathlib import Path

import simbench as sb

REFERENCE_DIR = Path(__file__).resolve().parent
REPO = REFERENCE_DIR.parent
FIXTURES = REPO / "test" / "references"

# Options for pp.runpp. Both of the first two are required: a flat init does not
# converge on the EHV grids. The tolerance is pandapower's own default; tightening it to
# 1e-10 makes the EHV grids fail to converge at all.
RUNPP = {
    "calculate_voltage_angles": True,
    "init": "auto",
    "numba": False,
    "tolerance_mva": 1e-8,
    "max_iteration": 100,
}

# The same run configured for _init_runpp_options, which takes every option explicitly.
# trafo_model="t" is pandapower's default and is the T model that SimBench._t_to_pi
# reproduces.
PD2PPC = {
    "algorithm": "nr",
    "calculate_voltage_angles": True,
    "init": "auto",
    "max_iteration": 100,
    "tolerance_mva": 1e-8,
    "trafo_model": "t",
    "trafo_loading": "current",
    "enforce_p_lims": False,
    "enforce_q_lims": False,
    "check_connectivity": True,
    "voltage_depend_loads": False,
    "numba": False,
}


def targets() -> dict:
    """The pinned code lists and filter subsets."""
    with (REFERENCE_DIR / "targets.toml").open("rb") as fh:
        return tomllib.load(fh)


def load_net(code: str):
    """Build the pandapower net for `code`, with both known traps handled."""
    net = sb.get_simbench_net(code)

    # The simbench converter writes only tap_phase_shifter, which is the pandapower 2
    # spelling. pandapower 3 reads tap_changer_type and skips the entire tap ratio
    # branch while it is empty, so the dataset's tappos is silently ignored and every
    # tap comes out at 1.0. Each SimBench TransformerType is tapable on the HV side
    # with dVa = 0, so "Ratio" is the correct type for all of them.
    if len(net.trafo):
        net.trafo["tap_changer_type"] = "Ratio"

    # Name keying only works if names identify elements uniquely.
    assert net.bus.name.is_unique, f"{code}: bus names are not unique"
    assert net.line.name.is_unique, f"{code}: line names are not unique"
    assert net.trafo.name.is_unique, f"{code}: trafo names are not unique"

    # A tap controller would act during runpp and move the reference off the dataset.
    assert not len(net.controller), f"{code}: unexpected controllers"

    return net


def build_ppc(net):
    """Build the ppc for `net` without running a power flow.

    Deliberately not via runpp: pandapower appends generators for every dcline inside
    the power flow and removes them afterwards, which leaves the gen lookups stale and
    silently misaligns name keying on the scenarios that have HVDC.
    """
    from pandapower.auxiliary import _init_runpp_options
    from pandapower.pd2ppc import _pd2ppc

    _init_runpp_options(net, **PD2PPC)
    # SimBench shares balancing between several slacks through dspf, which neither
    # pandapower nor PowerModels honours. They ignore it identically today; assert so
    # that a change of default is caught rather than absorbed.
    assert not net._options.get("distributed_slack", False)
    ppc, _ = _pd2ppc(net)
    return ppc


def fmt(x) -> str:
    """Format a float so Julia parses it back to the same bits.

    Python's repr is the shortest round-tripping form. NaN becomes an empty field, which
    Julia reads as `missing`, matching the package's own NULL convention.
    """
    if x is None:
        return ""
    v = float(x)
    if math.isnan(v):
        return ""
    if math.isinf(v):
        return "Inf" if v > 0 else "-Inf"
    return repr(v)


def boolean(x) -> str:
    """Format a boolean the way Julia's CSV reader expects it."""
    return "true" if x else "false"


def digest(ids) -> str:
    """Stable short digest of a sequence of element ids."""
    joined = "\n".join(str(i) for i in ids)
    return hashlib.sha256(joined.encode("utf-8")).hexdigest()[:16]


def write_csv(path: Path, header, rows) -> Path:
    """Write `rows` to `path`, with LF endings and a trailing newline."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, lineterminator="\n")
        writer.writerow(header)
        writer.writerows(rows)
    print(f"  wrote {path.relative_to(REPO)} ({len(rows)} rows)")
    return path
