# CLAUDE.md

SimBench.jl reads the SimBench benchmark grid dataset (CSV) and converts it to
PowerModels.jl network data. It is a read-only Julia port of the Python reference
implementation at `../simbench` (github.com/e2nIEE/simbench), which targets pandapower.
PowerModels is deliberately not a dependency; the package emits a plain data dict.

## Commands

```bash
julia --project=. -e 'using Pkg; Pkg.test()'   # full test suite, includes Aqua
prek run --all-files                           # all lint/format hooks, run before committing
julia --project=docs docs/make.jl              # build docs, includes doctests
```

Formatting is Runic (checked by a hook, not auto-applied). ExplicitImports enforces
`using Foo: bar` form; never add a bare `using`.

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
- `grid.jl`: `SimBenchGrid` and `read_grid`.
- `switches.jl`: resolves the busbar/switch/auxiliary-node topology by union-find
  fusion. A `no_sw` code collapses couplers; `sw` keeps them as low-impedance branches.
- `powermodels.jl`: `powermodels_data`. Follows pandapower's `pd2ppc` conventions:
  transformer impedance referred to the LV side, T-model magnetising branch converted
  to pi (`_t_to_pi`), off-nominal `tap` and Dyn5 `shift`. Output is per unit with
  angles in radians. Solver starting points go in `va_start`/`vm_start` (PowerModels
  ignores `va`/`vm` for that): angles from shift propagation plus a DC power flow,
  magnitudes at load buses from the mean controlled-bus setpoint. Both are load
  bearing; grids do not converge without them.

Nothing is exported; the API is `SimBench.`-qualified calls.

## Validation policy

Every layer is validated numerically against the Python reference, not by porting its
tests: codes against `simbench_code.py` enumeration, extraction against row counts and
id digests over 19 codes, per-unit values against pandapower's internal `ppc` arrays
(1e-12), power flow against `pp.runpp` (1e-8 or better where grids agree). When
touching the conversion, re-check against pandapower rather than reasoning from code.
A venv with `simbench` and `pandapower` plus `numba=False` suffices to regenerate
references.

Known accepted difference: a line with an open switch at one end is dropped entirely,
while pandapower keeps it energised from the closed end. This bounds MV grid agreement
at about 8e-4 in vm and is a documented modelling choice, not a bug.

## Tests

Dataset-dependent testsets skip (not fail) when the data is unavailable: they guard on
the `DATASET !== nothing` pattern from `test/runtests.jl`. Keep new tests offline-safe
the same way. `DATASET` honours `SIMBENCH_DATA_DIR`; `ARTIFACT_DIR` is always the
artifact.

## Conventions

- Commit messages: short, imperative subject; no chat or session links.
- `PLAN.md` and `EHV-CONVERGENCE.md` stay untracked; never commit them.
- No em dashes anywhere. Docs never mention development phases or `PLAN.md`.
- Update `CHANGELOG.md` (Keep a Changelog format) for user-visible changes; CI enforces
  it on PRs.
- Docstrings follow Documenter conventions; `docs/make.jl` runs with
  `checkdocs = :exports` and doctests.
