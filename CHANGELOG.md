# Changelog

Notable changes to SimBench.jl are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/).

## unreleased

### Changed

- A line open at exactly one end stays in service, with its open end on a stub bus,
  matching pandapower's switch model: the line is still energised from the closed end
  and its charging still draws reactive power. This closes the last modelling gap;
  every compared grid, across all voltage levels and scenarios, now agrees with
  pandapower to 1e-10 pu or better

- The default `coupler_impedance` is 1.0e-6 rather than 1.0e-5 per unit. The `sw`
  variants are now validated against pandapower across all voltage levels; voltage
  agreement scales linearly with this impedance, and Newton-Raphson tolerates one more
  order of magnitude before failing around 1.0e-7

### Added

- Time series and study cases: `absolute_profiles` turns the relative profiles into
  absolute MW and MVAr per element, `apply_profile!` and `apply_study_case!` set a
  PowerModels case to a time step or to one of the six study cases. `read_grid` now
  drops profile columns no element uses and reduces the study cases to the grid's
  voltage level, as the reference implementation does. Validated against it at machine
  precision over four grids spanning both modes

- HVDC links of scenarios 1 and 2 are converted: by default as the generator pair
  pandapower's power flow uses internally, which `compute_ac_pf` solves, or as
  PowerModels `dcline` components with `dc_as = :dcline`. `storage_as = :load` turns
  storage units into equivalent loads for `solve_ac_pf`, which rejects storage

- `powermodels_data`, converting a grid to PowerModels network data. The per-unit values
  match pandapower's internal arrays to floating point noise, and power flow results
  agree with pandapower on every voltage level, the extra-high included

- The dataset downloads itself on first use as a lazy `Pkg` artifact, pointing at the
  upstream project's PyPI release rather than a copy hosted here

- `resolve_topology`, collapsing auxiliary nodes and switches into a bus topology, in
  both the collapsed and the coupler-preserving variant
- Grid extraction by SimBench code, validated against the reference implementation over
  19 codes spanning every voltage level: same subnets, row counts and element ids
- `SimBenchGrid` and `read_grid`, reading any published grid into `DataFrame`s
- `SimBenchCode` for parsing, rendering and enumerating SimBench codes, cross-checked
  against the reference implementation over all 246 published codes
- CSV readers with the column schema of all 20 fixed tables, `NULL` handling and
  inferred profile columns
- Voltage level helpers
- Package skeleton: module, table inventory for the 17-to-20 table SimBench CSV format,
  and dataset location via `SimBench.set_data_dir!` or the `SIMBENCH_DATA_DIR`
  environment variable
- Test suite covering the table inventory and dataset resolution, plus Aqua
- Documenter site with doctests and an API reference
- CI: test matrix over Julia lts/1/pre on Linux, macOS and Windows; lint, spelling,
  link checking, CodeQL and release drafting
