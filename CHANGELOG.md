# Changelog

Notable changes to SimBench.jl are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/).

## unreleased

### Added

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
