# Contributing

Contributions are welcome. The package is an in-progress port, so the most useful
contributions right now are on the phases that are not done yet — see
[`PLAN.md`](https://github.com/langestefan/SimBench.jl/blob/main/PLAN.md) for the roadmap.

## Workflow

We work in the order: open an issue → discuss if needed → open a pull request. For a small
fix an issue is not required.

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
    `pre-commit install`. That is intentional — changes go through pull requests.

## Tests that need the dataset

The SimBench CSV dataset is 378 MB and is not bundled with the package. Tests that need it
skip themselves when it is not configured, so a plain `Pkg.test()` passes without it. To
run them, point the package at a local copy:

```bash
SIMBENCH_DATA_DIR=/path/to/simbench/simbench/networks julia --project=. -e 'using Pkg; Pkg.test()'
```

## Correctness

The conversion from SimBench CSV to PowerModels reimplements the per-unit conversion that
pandapower performs internally, so changes to `src/powermodels.jl` need to be validated
numerically against pandapower's power-flow results rather than by inspection. See
`PLAN.md` §6.
