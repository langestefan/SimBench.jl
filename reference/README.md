# Reference fixtures

SimBench.jl is validated numerically against the Python reference implementation rather
than by porting its tests. This directory holds the generator that captures those
reference values; the fixtures it writes live in [`test/references/`](../test/references).

The Julia tests only ever read the fixtures. They never call Python, so the suite stays
pure Julia and offline safe.

## Regenerating

```bash
uv run --project reference reference/generate_all.py
```

`uv` builds the environment from `uv.lock`, so the versions are identical for everyone.
On a clean checkout the regenerated fixtures must be byte identical to the committed
ones: an empty `git diff` afterwards is the proof that the fixtures match what the
generator produces.

The pinned dataset is `simbench 1.6.2` from PyPI, which is the same sdist that
`Artifacts.toml` points the Julia package at. Python and Julia therefore read identical
bytes, and nothing depends on a sibling checkout of the reference repository.

## What gets captured

| Fixture | Pins |
| --- | --- |
| `codes.csv` | the ordered enumeration of all 246 SimBench codes |
| `code_subsets.csv` | named filter combinations, by content rather than by count |
| `extractions.csv` | per code and table, row counts and element id digests |
| `ppc/<code>.*.csv` | pandapower's internal per-unit bus, branch, generator and HVDC values |
| `powerflow/<code>.bus.csv` | pandapower's power flow solution, per bus |
| `manifest.csv` | provenance, counts and the per-grid comparison tolerances |

Which grids are pinned is decided in [`targets.toml`](targets.toml), the single source of
truth for both sides.

## Two traps

Both are handled in `common.py` and nowhere else.

Transformer tap positions: the simbench converter only ever writes `tap_phase_shifter`,
which is the pandapower 2 spelling. pandapower 3 reads `tap_changer_type` instead and
skips the entire tap ratio branch while it is empty, so the dataset's `tappos` is
silently ignored and every tap comes out at 1.0. Every SimBench `TransformerType` is
tapable on the HV side with `dVa = 0`, so `"Ratio"` is the correct type for all of them.
The manifest records `tap_changer_type_applied` and the Julia test asserts it, so a
reference regenerated without the workaround fails loudly instead of quietly pinning
every tap at 1.0.

Power flow options: `pp.runpp` needs `calculate_voltage_angles=True` and `init="auto"`,
because a flat start does not converge on the EHV grids. The tolerance is pandapower's
own default; tightening it to 1e-10 makes the EHV grids fail to converge at all.

## Keying

Nothing is keyed by ppc row index. Buses key on SimBench node id and branches on element
name, because the two implementations legitimately differ in ways that would break any
positional comparison:

- When a `no_sw` code fuses a group of buses, upstream deletes the absorbed rows and
  keeps its own representative, while SimBench.jl keeps the lowest Node table index. The
  fixtures therefore never compare bus names. Instead the Julia test proves the two
  partitions are identical, by checking that the node to bus map is injective and that
  the counts agree.
- For an `sw` code pandapower fuses bus couplers inside the ppc, while SimBench.jl keeps
  them as low impedance branches. The Julia partition is then a refinement of
  pandapower's, and the coupler branches have no counterpart to compare against.

## Private pandapower API

`gen_ppc.py` uses `_init_runpp_options`, `_pd2ppc` and `_pd2ppc_lookups`, none of which
are public. The exact version pin keeps regeneration reproducible, but a pandapower bump
is a small porting task rather than a free upgrade.

The ppc is built without running a power flow on purpose. pandapower appends a generator
per HVDC link inside the power flow and removes it afterwards, which leaves the generator
lookups stale and would silently misalign name keying on the scenarios that have HVDC.
