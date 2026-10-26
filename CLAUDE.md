# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

SimBench.jl reads the SimBench benchmark grid dataset (CSV), converts it to
PowerModels.jl network data, and applies its time series profiles and study cases. It
is a read-only Julia port of the Python reference implementation at `../simbench`
(github.com/e2nIEE/simbench), which targets pandapower. PowerModels is deliberately not
a dependency; the package emits a plain data dict.

## Commands

```bash
julia --project=. -e 'using Pkg; Pkg.test()'   # full test suite, includes Aqua
prek run --all-files                           # all lint/format hooks, run before committing
prek run runic --all-files                     # one hook: runic, typos, explicit-imports
julia --project=docs docs/make.jl              # build docs, includes doctests
julia --project=validation validation/run.jl   # power flow against pandapower
uv run --project reference reference/generate_all.py   # regenerate the reference fixtures
```

Regeneration must be a no-op on a clean checkout: an empty `git diff` afterwards is the
proof that the committed fixtures are what the generator produces.

One test file, without the rest of the suite. The files are `include`d by
`test/runtests.jl` and read the two constants it defines, so redefine them first:

```bash
julia --project=. -e '
using SimBench, Test
const DATASET = SimBench.data_dir()
const ARTIFACT_DIR = SimBench.artifact_data_dir()
include("test/test_powermodels.jl")'
```

`test_codes.jl`, `test_extract.jl` and `test_reference_ppc.jl` also use the fixture
helpers (`read_reference`, `id_digest`, ...), so `include("test/references.jl")` before
them.

Formatting is Runic (checked by a hook, not auto-applied). ExplicitImports enforces
`using Foo: bar` form; never add a bare `using`.

After adding a `[deps]` entry, run `Pkg.resolve()` before testing or linting; the
`explicit-imports` hook fails with a `KeyError` on a stale `Manifest.toml`. The docs
environment needs the same treatment separately, and it builds through
DocumenterVitepress, so `docs/node_modules` and a working `npm` are required. The docs
build executes `docs/src/plotting.md`, which loads PowerModels and PowerPlots, so it
solves power flows and is slow.

`examples/` is a fourth environment (GLMakie, PowerPlotsMakie). Its `[sources]` resolve
SimBench from `..` and PowerPlotsMakie from a sibling checkout `../../PowerPlotsMakie.jl`,
and need Julia 1.11+. See `examples/README.md`.

CI's Lint job also runs a lychee link check over the repository, which the local hooks
do not cover; a dead link in Markdown passes `prek` and fails CI.

## Architecture

Two layers, so the electrical model is testable independently of CSV parsing:

```text
CSV files -> SimBenchGrid (DataFrames, SimBench units) -> PowerModels dict (per unit)
```

`src/` include order matters (later files use earlier definitions):

- `schema.jl`: the 24 table names, column names and types of the SimBench CSV format.
  Column names like `vmSetp`, `tapNeutr` are file-format identifiers; never "fix" their
  spelling (pinned in `.typos.toml`).
- `data_source.jl`: dataset location. Resolution order: `set_data_dir!`, then the
  `SIMBENCH_DATA_DIR` env var, then the lazy artifact. `Artifacts.toml` points at the
  upstream PyPI sdist (immutable), not a copy hosted here.
- `codes.jl`: `SimBenchCode` parsing and enumeration of all 246 published codes.
- `voltlvl.jl`, `io.jl`: voltage level helpers; CSV readers (`;` separator, `NULL`
  sentinel).
- `extract.jl`: selects one benchmark grid out of a complete-data scenario by subnet,
  faithfully reproducing the reference implementation, including its dead
  `lv_hv_elms` branch (verified always empty upstream).
- `grid.jl`: `SimBenchGrid` and `read_grid`. `read_grid(...; cache = true)` keeps the
  parsed complete-data scenario in a module-level cache (emptied by
  `clear_scenario_cache!`), so reading many codes from one scenario parses its CSVs once.
- `switches.jl`: resolves the busbar/switch/auxiliary-node topology by union-find
  fusion. A `no_sw` code collapses couplers; `sw` keeps them as low-impedance branches.
- `powermodels.jl`: `powermodels_data`. Follows pandapower's `pd2ppc` conventions:
  transformer impedance referred to the LV side, T-model magnetising branch converted
  to pi (`_t_to_pi`), off-nominal `tap` and Dyn5 `shift`. Output is per unit with
  angles in radians. Solver starting points go in `va_start`/`vm_start` (PowerModels
  ignores `va`/`vm` for that): angles from shift propagation plus a DC power flow,
  magnitudes at load buses from the mean controlled-bus setpoint. Both are load
  bearing; grids do not converge without them. Also `attach_coordinates!`, which writes
  the `Coordinates` table into the `xcoord_1`/`ycoord_1` keys PowerPlots reads.
- `profiles.jl`: `absolute_profiles` (relative profiles times base powers, MW/MVAr),
  `apply_profile!` and `apply_study_case!` (snapshot a PowerModels dict, matching
  elements through `source_id` and dividing by `baseMVA`). `read_grid` drops unused
  profile columns and reduces StudyCases to the grid's voltage level, as upstream's
  `get_simbench_net` does.

Only the core workflow is exported: `SimBenchGrid`, `SimBenchCode`,
`all_simbench_codes`, `read_grid`, `powermodels_data`, `absolute_profiles`,
`apply_profile!` and `apply_study_case!`. Everything below that layer stays a
`SimBench.`-qualified call. Exporting a name puts it under `checkdocs = :exports`, so it
needs a docstring or the docs build fails.

Conversion has to stay linear in element count. The `EHVHVMVLV` codes combine
transmission and distribution into roughly 38,000 buses, where anything quadratic in bus
count exhausts memory; this is why `_refine_angles_dc!` assembles its susceptance matrix
sparse. Convert grids that large in a separate process rather than a shared REPL.

## Validation policy

Every layer is validated numerically against the Python reference, not by porting its
tests. The reference values are captured into fixtures under `test/references/` by the
generator in `reference/`, and the tests assert against those fixtures; nothing is
transcribed by hand. See `reference/README.md`.

What is pinned: the ordered 246-code enumeration and named filter subsets; extraction row
counts plus two element-id digests, ordered and sorted, per table over 18 codes;
pandapower's internal `ppc` per-unit values over 10 grids spanning LV to EHV; and
pandapower's power flow solution for the same 10.

The power flow comparison lives in the separate `validation/` environment and its own CI
job, because PowerModels is not a package dependency and the main suite runs on a 7-leg
matrix across 3 operating systems. It uses `PowerModels.compute_ac_pf`, a native
Newton-Raphson needing no optimizer, which reads `vm_start`/`va_start`, so a converging
run also regression-tests the angle and magnitude seeding.

Measured agreement, recorded as per-grid tolerances in `test/references/manifest.csv`:
5e-15 relative on branch impedance, 3e-14 absolute on the pi shunt terms, 8e-12 MW on
aggregated nodal injections, and voltages to 1e-12 pu on the `no_sw` grids. When touching
the conversion, re-check against pandapower rather than reasoning from code.

Traps when comparing against pandapower 3. All three are handled in
`reference/common.py` and nowhere else:

- Transformer tap positions: the simbench converter never sets `tap_changer_type`, so
  pandapower 3 silently ignores the dataset's `tappos` (pandapower 2 applied it). This
  package applies taps, as the data intends. When regenerating references, set
  `net.trafo["tap_changer_type"] = "Ratio"` first or MV grids disagree by ~1.5e-2. The
  manifest records `tap_changer_type_applied` and the tests assert it, so a reference
  regenerated into this trap fails loudly instead of pinning every tap at 1.0.
- `pp.runpp` needs `calculate_voltage_angles=True` and `init="auto"`; a flat init does
  not converge on the EHV grids.
- Leave `tolerance_mva` at pandapower's default. Tightening it to 1e-10 makes the EHV
  grids fail to converge at all.

Comparisons key on SimBench names, never on positions, because the two implementations
differ in ways that break positional matching. Buses key on node id: `no_sw` fusion keeps
different representatives on each side, so the tests prove the partitions match by
injectivity plus equal counts rather than comparing names. `sw` grids keep couplers as
`1e-6` pu branches where pandapower fuses ideally, so this side is a refinement of
pandapower's partition and voltages agree only to a few 1e-6. Angles are compared modulo
a full turn: cascaded Dyn5 transformers shift 150 degrees each, and the two sides can
report the same angle a turn apart.

## Tests

Dataset-dependent testsets skip (not fail) when the data is unavailable: they guard on
the `DATASET !== nothing` pattern from `test/runtests.jl`. Keep new tests offline-safe
the same way. `DATASET` honours `SIMBENCH_DATA_DIR`; `ARTIFACT_DIR` is always the
artifact.

## Conventions

- Commit messages: short, imperative subject; no chat or session links. Keep commits
  small and self-contained rather than batching unrelated work into one.
- `PLAN.md` and `EHV-CONVERGENCE.md` stay untracked; never commit them.
- No em dashes anywhere. Docs never mention development phases or `PLAN.md`.
- Update `CHANGELOG.md` (Keep a Changelog format) for user-visible changes; CI enforces
  it on PRs.
- Docstrings follow Documenter conventions; `docs/make.jl` runs with
  `checkdocs = :exports` and doctests.
