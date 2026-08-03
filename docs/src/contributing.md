# Contributing

Contributions are welcome. The package is an in-progress port, so the most useful
contributions right now are on the parts that are not implemented yet: CSV parsing, grid
extraction, the PowerModels conversion, and time series handling.

## Workflow

We work in the order: open an issue, discuss if needed, then open a pull request. For a
small fix an issue is not required.

1. Fork the repository and create a branch off `main`.
2. Make your change, with tests.
3. Add an entry to `CHANGELOG.md` under `## unreleased`, or label the PR `skip-changelog`.
4. Open a pull request and fill in the template.

## Running the checks locally

```bash
julia --project=. -e 'using Pkg; Pkg.test()'          # test suite
julia --project=docs docs/make.jl                     # docs and doctests
pre-commit run -a                                     # formatting and linting
```

[`pre-commit`](https://pre-commit.com/) runs [Runic](https://github.com/fredrikekre/Runic.jl)
for Julia formatting, ExplicitImports, markdownlint, yamllint and typos. Install it with
`pip install pre-commit`, then `pre-commit install` to run it on every commit.

!!! note
    The `no-commit-to-branch` hook blocks direct commits to `main` once you have run
    `pre-commit install`. That is intentional, since changes go through pull requests.

## Tests that need the dataset

Most of the suite runs against the real dataset, which the test run downloads once as a
lazy artifact. The first `Pkg.test()` on a fresh machine therefore fetches 88 MB. To run
against a local copy instead:

```bash
SIMBENCH_DATA_DIR=/path/to/simbench/simbench/networks julia --project=. -e 'using Pkg; Pkg.test()'
```

Tests needing real data skip themselves if it can be obtained neither way, so the suite
still passes offline, with a warning and a reduced count.

## Correctness

The conversion from SimBench CSV to PowerModels reimplements the per-unit conversion that
pandapower performs internally, so changes to the conversion need to be validated
numerically against pandapower's power-flow results rather than by inspection.
