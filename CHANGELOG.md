# Changelog

Notable changes to SimBench.jl are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/).

## unreleased

### Added

- Package skeleton: module, table inventory for the 17-to-20 table SimBench CSV format,
  and dataset location via `SimBench.set_data_dir!` or the `SIMBENCH_DATA_DIR`
  environment variable
- Test suite covering the table inventory and dataset resolution, plus Aqua
- Documenter site with doctests and an API reference
- CI: test matrix over Julia lts/1/pre on Linux, macOS and Windows; lint, spelling,
  link checking, CodeQL and release drafting
